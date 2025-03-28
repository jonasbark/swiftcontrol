// BLEServer.cpp : Windows 10 Web Bluetooth Polyfill Server
//
// Copyright (C) 2017, Uri Shaked. License: MIT.
//

#include "stdafx.h"
#include <iostream>
#include <Windows.Foundation.h>
#include <Windows.Devices.Bluetooth.h>
#include <Windows.Devices.Bluetooth.Advertisement.h>
#include <Windows.Data.JSON.h>
#include <Windows.Storage.Streams.h>
#include <wrl/wrappers/corewrappers.h>
#include <wrl/event.h>
#include <collection.h>
#include <ppltasks.h>
#include <string>
#include <sstream>
#include <iomanip>
#include <experimental/resumable>
#include <pplawait.h>
#include <cvt/wstring>
#include <codecvt>
#include <stdio.h>
#include <fcntl.h>
#include <io.h>

using namespace Platform;
using namespace Windows::Foundation::Collections;
using namespace Windows::Devices;
using namespace Windows::Devices::Radios;
using namespace Windows::Data::Json;
using namespace concurrency;

Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher ^ bleAdvertisementWatcher;
auto devices = ref new Collections::Map<String ^, Bluetooth::BluetoothLEDevice ^>();
auto characteristicsMap = ref new Collections::Map<String ^, Bluetooth::GenericAttributeProfile::GattCharacteristic ^>();
auto characteristicsListenerMap = ref new Collections::Map<String ^, Windows::Foundation::EventRegistrationToken>();
auto characteristicsSubscriptionMap = ref new Collections::Map<String ^, JsonValue ^>();

std::wstring formatBluetoothAddress(unsigned long long BluetoothAddress)
{
	std::wostringstream ret;
	ret << std::hex << std::setfill(L'0')
		<< std::setw(2) << ((BluetoothAddress >> (5 * 8)) & 0xff) << ":"
		<< std::setw(2) << ((BluetoothAddress >> (4 * 8)) & 0xff) << ":"
		<< std::setw(2) << ((BluetoothAddress >> (3 * 8)) & 0xff) << ":"
		<< std::setw(2) << ((BluetoothAddress >> (2 * 8)) & 0xff) << ":"
		<< std::setw(2) << ((BluetoothAddress >> (1 * 8)) & 0xff) << ":"
		<< std::setw(2) << ((BluetoothAddress >> (0 * 8)) & 0xff);
	return ret.str();
}

Guid parseUuid(String ^ uuid)
{
	if (uuid->Length() == 4)
	{
		unsigned int uuidShort = std::stoul(uuid->Data(), 0, 16);
		return Bluetooth::BluetoothUuidHelper::FromShortId(uuidShort);
	}
	GUID rawguid;
	if (SUCCEEDED(IIDFromString(uuid->Data(), &rawguid)))
	{
		return Guid(rawguid);
	}
	else
	{
		std::wstring msg = L"Invalid UUID: ";
		msg += uuid->Data();
		throw ref new InvalidArgumentException(ref new String(msg.c_str()));
	}
}

union uint16_t_union
{
	uint16_t uint16;
	byte bytes[sizeof(uint16_t)];
};

CRITICAL_SECTION OutputCriticalSection;

void writeObject(JsonObject ^ jsonObject)
{
	String ^ jsonString = jsonObject->Stringify();

	stdext::cvt::wstring_convert<std::codecvt_utf8<wchar_t>> convert;
	std::string stringUtf8 = convert.to_bytes(jsonString->Data());

	auto len = stringUtf8.length();

	EnterCriticalSection(&OutputCriticalSection);
	std::cout << char(len >> 0)
			  << char(len >> 8)
			  << char(len >> 16)
			  << char(len >> 24);

	std::cout << stringUtf8 << std::flush;
	LeaveCriticalSection(&OutputCriticalSection);
}

concurrency::task<IJsonValue ^> connectRequest(JsonObject ^ command)
{
	String ^ addressStr = command->GetNamedString("address", "");
	unsigned long long address = std::stoull(addressStr->Data(), 0, 16);
	auto device = co_await Bluetooth::BluetoothLEDevice::FromBluetoothAddressAsync(address);

	if (device == nullptr)
	{
		throw ref new FailureException(ref new String(L"Device not found (null)"));
	}
	devices->Insert(device->DeviceId, device);
	device->ConnectionStatusChanged += ref new Windows::Foundation::TypedEventHandler<Bluetooth::BluetoothLEDevice ^, Platform::Object ^>(
		[](Windows::Devices::Bluetooth::BluetoothLEDevice ^ device, Platform::Object ^ eventArgs)
		{
			if (device->ConnectionStatus == Bluetooth::BluetoothConnectionStatus::Disconnected)
			{
				JsonObject ^ msg = ref new JsonObject();
				msg->Insert("_type", JsonValue::CreateStringValue("disconnectEvent"));
				msg->Insert("device", JsonValue::CreateStringValue(device->DeviceId));
				writeObject(msg);
				devices->Remove(device->DeviceId);
			}
		});
	co_return JsonValue::CreateStringValue(device->DeviceId);
}

auto CustomOnPairingRequested = ref new Windows::Foundation::TypedEventHandler<Enumeration::DeviceInformationCustomPairing ^, Enumeration::DevicePairingRequestedEventArgs ^>([](Windows::Devices::Enumeration::DeviceInformationCustomPairing ^ sender, Windows::Devices::Enumeration::DevicePairingRequestedEventArgs ^ eventArgs)
																																											  { eventArgs->Accept(); });

concurrency::task<IJsonValue ^> pairRequest(JsonObject ^ command)
{
	String ^ deviceId = command->GetNamedString("device", "");

	if (!devices->HasKey(deviceId))
	{
		throw ref new FailureException(ref new String(L"Device not found"));
	}
	Bluetooth::BluetoothLEDevice ^ device = devices->Lookup(deviceId);

	Windows::Foundation::EventRegistrationToken cookie = device->DeviceInformation->Pairing->Custom->PairingRequested += CustomOnPairingRequested;

	auto result = co_await device->DeviceInformation->Pairing->Custom->PairAsync(Enumeration::DevicePairingKinds::ConfirmOnly, Enumeration::DevicePairingProtectionLevel::None);

	device->DeviceInformation->Pairing->Custom->PairingRequested -= cookie;

	bool canPair = device->DeviceInformation->Pairing->CanPair;

	bool isPaired = device->DeviceInformation->Pairing->IsPaired;

	co_return JsonValue::CreateStringValue(result->Status.ToString());
}

JsonValue ^ canPair(JsonObject ^ command) {
	String ^ deviceId = command->GetNamedString("device", "");
	if (!devices->HasKey(deviceId))
	{
		throw ref new FailureException(ref new String(L"Device not found"));
	}
	Bluetooth::BluetoothLEDevice ^ device = devices->Lookup(deviceId);
	bool canPair = device->DeviceInformation->Pairing->CanPair;

	return JsonValue::CreateBooleanValue(canPair);
}

	concurrency::task<IJsonValue ^> isPaired(JsonObject ^ command)
{
	String ^ deviceId = command->GetNamedString("device", "");
	bool forceRefresh = command->GetNamedBoolean("forceRefresh", false);
	if (forceRefresh || !devices->HasKey(deviceId))
	{
		unsigned long long address = std::stoull(deviceId->Data(), 0, 16);
		Bluetooth::BluetoothLEDevice ^ device = co_await Bluetooth::BluetoothLEDevice::FromBluetoothAddressAsync(address);
		co_return JsonValue::CreateBooleanValue(device->DeviceInformation->Pairing->IsPaired);
	}
	else if (devices->HasKey(deviceId))
	{
		Bluetooth::BluetoothLEDevice ^ device = devices->Lookup(deviceId);
		co_return JsonValue::CreateBooleanValue(device->DeviceInformation->Pairing->IsPaired);
	}

	throw ref new FailureException(ref new String(L"Device not found"));
}

concurrency::task<IJsonValue ^> unPairRequest(JsonObject ^ command)
{
	String ^ deviceId = command->GetNamedString("device", "");
	if (!devices->HasKey(deviceId))
	{
		throw ref new FailureException(ref new String(L"Device not found"));
	}
	Bluetooth::BluetoothLEDevice ^ device = devices->Lookup(deviceId);

	auto result = co_await device->DeviceInformation->Pairing->UnpairAsync();

	bool canPair = device->DeviceInformation->Pairing->CanPair;
	bool isPaired = device->DeviceInformation->Pairing->IsPaired;

	co_return JsonValue::CreateStringValue(result->Status.ToString());
}

Concurrency::task<IJsonValue ^> disconnectRequest(JsonObject ^ command)
{
	String ^ deviceId = command->GetNamedString("device", "");
	if (!devices->HasKey(deviceId))
	{
		throw ref new FailureException(ref new String(L"Device not found"));
	}
	Bluetooth::BluetoothLEDevice ^ device = devices->Lookup(deviceId);

	// When disconnecting from a device, also remove all the characteristics from our cache.
	auto newCharacteristicsMap = ref new Collections::Map<String ^, Bluetooth::GenericAttributeProfile::GattCharacteristic ^>();
	for (auto pair : characteristicsMap)
	{
		bool removed = true;
		try
		{
			auto service = pair->Value->Service;
			if (service->Device->DeviceId->Equals(device->DeviceId))
			{
				delete service->Device;
				delete service;
			}
			else
			{
				newCharacteristicsMap->Insert(pair->Key, pair->Value);
				removed = false;
			}
		}
		catch (...)
		{
			// Service is probably already closed, so we just skip it and it will be removed from the list
		}

		if (removed)
		{
			if (characteristicsListenerMap->HasKey(pair->Key))
			{
				characteristicsListenerMap->Remove(pair->Key);
			}
			if (characteristicsSubscriptionMap->HasKey(pair->Key))
			{
				characteristicsSubscriptionMap->Remove(pair->Key);
			}
		}
	}
	characteristicsMap = newCharacteristicsMap;
	devices->Remove(deviceId);

	return Concurrency::task_from_result<IJsonValue ^>(JsonValue::CreateNullValue());
}

concurrency::task<Bluetooth::GenericAttributeProfile::GattDeviceServicesResult ^> findServices(JsonObject ^ command)
{
	String ^ deviceId = command->GetNamedString("device", "");
	if (!devices->HasKey(deviceId))
	{
		throw ref new FailureException(ref new String(L"Device not found"));
	}
	Bluetooth::BluetoothLEDevice ^ device = devices->Lookup(deviceId);
	if (command->HasKey("service"))
	{
		if (command->GetNamedBoolean("forceRefresh", false))
		{
			return co_await device->GetGattServicesForUuidAsync(parseUuid(command->GetNamedString("service")), Bluetooth::BluetoothCacheMode::Uncached);
		}
		else
		{
			co_return co_await device->GetGattServicesForUuidAsync(parseUuid(command->GetNamedString("service")));
		}
	}
	else
	{
		if (command->GetNamedBoolean("forceRefresh", false))
		{
			co_return co_await device->GetGattServicesAsync(Bluetooth::BluetoothCacheMode::Uncached);
		}
		else
		{
			co_return co_await device->GetGattServicesAsync();
		}
	}
}

String ^ characteristicKey(String ^ device, String ^ service, String ^ characteristic) {
	std::wstring result = device->Data();
	result += L"//";
	result += service->Data();
	result += L"//";
	result += characteristic->Data();
	return ref new String(result.c_str());
}

	String
	^ characteristicKey(JsonObject ^ command) {
		  return characteristicKey(command->GetNamedString("device"), command->GetNamedString("service"), command->GetNamedString("characteristic"));
	  }

	concurrency::task<Bluetooth::GenericAttributeProfile::GattCharacteristicsResult ^> findCharacteristics(JsonObject ^ command)
{
	if (!command->HasKey("service"))
	{
		throw ref new InvalidArgumentException(ref new String(L"Service uuid must be provided"));
	}
	auto servicesResult = co_await findServices(command);
	auto services = servicesResult->Services;
	if (services->Size == 0)
	{
		throw ref new FailureException(ref new String(L"Requested service not found"));
	}
	auto service = services->GetAt(0);

	bool forceRefresh = command->GetNamedBoolean("forceRefresh", false);

	auto results = forceRefresh ? co_await service->GetCharacteristicsAsync(Bluetooth::BluetoothCacheMode::Uncached) : co_await service->GetCharacteristicsAsync();
	for (unsigned int i = 0; i < results->Characteristics->Size; i++)
	{
		auto characteristic = results->Characteristics->GetAt(i);
		auto key = characteristicKey(command->GetNamedString("device"), command->GetNamedString("service"), characteristic->Uuid.ToString());
		characteristicsMap->Insert(key, characteristic);
	}
	co_return results;
}

concurrency::task<Bluetooth::GenericAttributeProfile::GattCharacteristic ^> getCharacteristic(JsonObject ^ command)
{
	if (!command->HasKey("characteristic"))
	{
		throw ref new InvalidArgumentException(ref new String(L"Characteristic uuid must be provided"));
	}

	auto key = characteristicKey(command);
	if (!characteristicsMap->HasKey(key))
	{
		co_await findCharacteristics(command);
	}

	if (characteristicsMap->HasKey(key))
	{
		co_return characteristicsMap->Lookup(key);
	}

	throw ref new FailureException(ref new String(L"Requested characteristic not found"));
}

concurrency::task<IJsonValue ^> servicesRequest(JsonObject ^ command)
{
	auto servicesResult = co_await findServices(command);
	auto result = ref new JsonArray();
	for (unsigned int i = 0; i < servicesResult->Services->Size; i++)
	{
		result->Append(JsonValue::CreateStringValue(servicesResult->Services->GetAt(i)->Uuid.ToString()));
	}
	co_return result;
}

concurrency::task<IJsonValue ^> charactersticsRequest(JsonObject ^ command)
{
	auto characteristicsResult = co_await findCharacteristics(command);
	auto result = ref new JsonArray();
	for (unsigned int i = 0; i < characteristicsResult->Characteristics->Size; i++)
	{
		auto characteristic = characteristicsResult->Characteristics->GetAt(i);
		auto characteristicJson = ref new JsonObject();
		auto properties = ref new JsonObject();
		auto props = (unsigned int)characteristic->CharacteristicProperties;
		properties->SetNamedValue("broadcast", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::Broadcast));
		properties->SetNamedValue("read", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::Read));
		properties->SetNamedValue("writeWithoutResponse", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::WriteWithoutResponse));
		properties->SetNamedValue("write", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::Write));
		properties->SetNamedValue("notify", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::Notify));
		properties->SetNamedValue("indicate", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::Indicate));
		properties->SetNamedValue("authenticatedSignedWrites", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::AuthenticatedSignedWrites));
		properties->SetNamedValue("reliableWrite", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::ReliableWrites));
		properties->SetNamedValue("writableAuxiliaries", JsonValue::CreateBooleanValue(props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::WritableAuxiliaries));
		characteristicJson->SetNamedValue("uuid", JsonValue::CreateStringValue(characteristic->Uuid.ToString()));
		characteristicJson->SetNamedValue("properties", properties);
		result->Append(characteristicJson);
	}
	co_return result;
}

concurrency::task<IJsonValue ^> readRequest(JsonObject ^ command)
{
	auto characteristic = co_await getCharacteristic(command);
	auto result = co_await characteristic->ReadValueAsync();
	if (result->Status != Bluetooth::GenericAttributeProfile::GattCommunicationStatus::Success)
	{
		throw ref new FailureException(result->Status.ToString());
	}
	auto reader = Windows::Storage::Streams::DataReader::FromBuffer(result->Value);
	auto valueArray = ref new JsonArray();
	for (unsigned int i = 0; i < result->Value->Length; i++)
	{
		valueArray->Append(JsonValue::CreateNumberValue(reader->ReadByte()));
	}
	co_return valueArray;
}

concurrency::task<IJsonValue ^> writeRequest(JsonObject ^ command)
{
	auto characteristic = co_await getCharacteristic(command);
	auto writer = ref new Windows::Storage::Streams::DataWriter();
	auto dataArray = command->GetNamedArray("value");
	for (unsigned int i = 0; i < dataArray->Size; i++)
	{
		writer->WriteByte((unsigned char)dataArray->GetNumberAt(i));
	}
	// bool writeWithoutResponse = (unsigned int)characteristic->CharacteristicProperties & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::WriteWithoutResponse;
	// auto writeType = writeWithoutResponse ? Bluetooth::GenericAttributeProfile::GattWriteOption::WriteWithoutResponse : Bluetooth::GenericAttributeProfile::GattWriteOption::WriteWithResponse;
	bool writeWithResponse = command->GetNamedBoolean("writeWithResponse");
	auto writeType = writeWithResponse ? Bluetooth::GenericAttributeProfile::GattWriteOption::WriteWithResponse : Bluetooth::GenericAttributeProfile::GattWriteOption::WriteWithoutResponse;
	auto status = co_await characteristic->WriteValueAsync(writer->DetachBuffer(), writeType);
	if (status != Bluetooth::GenericAttributeProfile::GattCommunicationStatus::Success)
	{
		throw ref new FailureException(status.ToString());
	}

	co_return JsonValue::CreateNullValue();
}

unsigned long nextSubscriptionId = 1;

concurrency::task<IJsonValue ^> subscribeRequest(JsonObject ^ command)
{
	auto characteristic = co_await getCharacteristic(command);

	auto props = (unsigned int)characteristic->CharacteristicProperties;

	if (props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::Notify)
	{
		auto status = co_await characteristic->WriteClientCharacteristicConfigurationDescriptorAsync(Bluetooth::GenericAttributeProfile::GattClientCharacteristicConfigurationDescriptorValue::Notify);
		if (status != Bluetooth::GenericAttributeProfile::GattCommunicationStatus::Success)
		{
			throw ref new FailureException(status.ToString());
		}
	}
	else if (props & (unsigned int)Bluetooth::GenericAttributeProfile::GattCharacteristicProperties::Indicate)
	{
		auto status = co_await characteristic->WriteClientCharacteristicConfigurationDescriptorAsync(Bluetooth::GenericAttributeProfile::GattClientCharacteristicConfigurationDescriptorValue::Indicate);
		if (status != Bluetooth::GenericAttributeProfile::GattCommunicationStatus::Success)
		{
			throw ref new FailureException(status.ToString());
		}
	}
	else
	{
		throw ref new FailureException("Operation not supported.");
	}

	auto key = characteristicKey(command);
	if (characteristicsSubscriptionMap->HasKey(key))
	{
		co_return characteristicsSubscriptionMap->Lookup(key);
	}

	auto subscriptionId = JsonValue::CreateNumberValue(nextSubscriptionId++);

	Windows::Foundation::EventRegistrationToken cookie =
		characteristic->ValueChanged += ref new Windows::Foundation::TypedEventHandler<Bluetooth::GenericAttributeProfile::GattCharacteristic ^, Bluetooth::GenericAttributeProfile::GattValueChangedEventArgs ^>(
			[subscriptionId](Bluetooth::GenericAttributeProfile::GattCharacteristic ^ characteristic, Bluetooth::GenericAttributeProfile::GattValueChangedEventArgs ^ eventArgs)
			{
				JsonObject ^ msg = ref new JsonObject();
				msg->Insert("_type", JsonValue::CreateStringValue("valueChangedNotification"));
				msg->Insert("subscriptionId", subscriptionId);
				auto reader = Windows::Storage::Streams::DataReader::FromBuffer(eventArgs->CharacteristicValue);
				auto valueArray = ref new JsonArray();
				for (unsigned int i = 0; i < eventArgs->CharacteristicValue->Length; i++)
				{
					valueArray->Append(JsonValue::CreateNumberValue(reader->ReadByte()));
				}
				msg->Insert("value", valueArray);
				writeObject(msg);
			});

	characteristicsListenerMap->Insert(key, cookie);
	characteristicsSubscriptionMap->Insert(key, subscriptionId);

	co_return subscriptionId;
}

concurrency::task<IJsonValue ^> unsubscribeRequest(JsonObject ^ command)
{
	auto characteristic = co_await getCharacteristic(command);

	auto status = co_await characteristic->WriteClientCharacteristicConfigurationDescriptorAsync(Bluetooth::GenericAttributeProfile::GattClientCharacteristicConfigurationDescriptorValue::None);
	if (status != Bluetooth::GenericAttributeProfile::GattCommunicationStatus::Success)
	{
		throw ref new FailureException(status.ToString());
	}

	auto key = characteristicKey(command);

	if (characteristicsListenerMap->HasKey(key))
	{
		characteristic->ValueChanged -= characteristicsListenerMap->Lookup(key);
	}

	auto subscriptionId = characteristicsSubscriptionMap->Lookup(key);

	characteristicsListenerMap->Remove(key);
	characteristicsSubscriptionMap->Remove(key);

	co_return subscriptionId;
}

concurrency::task<IJsonValue ^> getRadioState()
{
	auto radios = co_await Radio::GetRadiosAsync();
	String ^ bleState = "";
	for (Windows::Devices::Radios::Radio ^ radio : radios)
	{
		if (radio->Kind == RadioKind::Bluetooth)
		{
			bleState = radio->State.ToString();
		}
	}
	co_return JsonValue::CreateStringValue(bleState);
}

concurrency::task<IJsonValue ^> changeRadioState(JsonObject ^ command)
{
	auto radios = co_await Radio::GetRadiosAsync();
	for (Windows::Devices::Radios::Radio ^ radio : radios)
	{
		if (radio->Kind == RadioKind::Bluetooth)
		{
			bool turnOn = command->GetNamedBoolean("turnOn");
			auto radioState = turnOn ? RadioState::On : RadioState::Off;
			co_await radio->SetStateAsync(radioState);
		}
	}
	co_return JsonValue::CreateNullValue();
}

concurrency::task<IJsonValue ^> getMaxMtuSize(JsonObject ^ command)
{
	String ^ deviceId = command->GetNamedString("device", "");
	if (!devices->HasKey(deviceId))
	{
		throw ref new FailureException(ref new String(L"Device not found"));
	}
	Bluetooth::BluetoothLEDevice ^ device = devices->Lookup(deviceId);
	auto gattSession = co_await Bluetooth::GenericAttributeProfile::GattSession::FromDeviceIdAsync(device->BluetoothDeviceId);
	auto size = gattSession->MaxPduSize;
	co_return JsonValue::CreateNumberValue(size);
}

concurrency::task<void> processCommand(JsonObject ^ command)
{
	String ^ cmd = command->GetNamedString("cmd", "");
	JsonObject ^ response = ref new JsonObject();
	IJsonValue ^ result = nullptr;
	response->Insert("_type", JsonValue::CreateStringValue("response"));
	response->Insert("_id", command->GetNamedValue("_id", JsonValue::CreateNullValue()));
	try
	{
		if (cmd->Equals("version"))
		{
			// Make sure to increment this version on each change
			result = JsonValue::CreateStringValue("1.0.0");
		}
		if (cmd->Equals("ping"))
		{
			result = JsonValue::CreateStringValue("pong");
		}
		if (cmd->Equals("scan"))
		{
			bleAdvertisementWatcher->Start();
			result = JsonValue::CreateNullValue();
		}
		if (cmd->Equals("radioState"))
		{
			result = co_await getRadioState();
		}
		if (cmd->Equals("changeRadioState"))
		{
			result = co_await changeRadioState(command);
		}
		if (cmd->Equals("stopScan"))
		{
			bleAdvertisementWatcher->Stop();
			result = JsonValue::CreateNullValue();
		}
		if (cmd->Equals("getMaxMtuSize"))
		{
			result = co_await getMaxMtuSize(command);
		}
		if (cmd->Equals("connect"))
		{
			result = co_await connectRequest(command);
		}
		if (cmd->Equals("canPair"))
		{
			result = canPair(command);
		}
		if (cmd->Equals("isPaired"))
		{
			result = co_await isPaired(command);
		}
		if (cmd->Equals("pair"))
		{
			result = co_await pairRequest(command);
		}

		if (cmd->Equals("unPair"))
		{
			result = co_await unPairRequest(command);
		}

		if (cmd->Equals("disconnect"))
		{
			result = co_await disconnectRequest(command);
		}

		if (cmd->Equals("services"))
		{
			result = co_await servicesRequest(command);
		}

		if (cmd->Equals("characteristics"))
		{
			result = co_await charactersticsRequest(command);
		}

		if (cmd->Equals("read"))
		{
			result = co_await readRequest(command);
		}

		if (cmd->Equals("write"))
		{
			result = co_await writeRequest(command);
		}

		if (cmd->Equals("subscribe"))
		{
			result = co_await subscribeRequest(command);
		}

		if (cmd->Equals("unsubscribe"))
		{
			result = co_await unsubscribeRequest(command);
		}

		if (result != nullptr)
		{
			response->Insert("result", result);
		}
		else
		{
			response->Insert("error", JsonValue::CreateStringValue("Unknown command"));
		}
		writeObject(response);
	}
	catch (Exception ^ e)
	{
		response->Insert("error", JsonValue::CreateStringValue(e->ToString()));
		writeObject(response);
	}
	catch (...)
	{
		response->Insert("error", JsonValue::CreateStringValue("Unknown error"));
		writeObject(response);
	}
}

int main(Array<String ^> ^ args)
{
	Microsoft::WRL::Wrappers::RoInitializeWrapper initialize(RO_INIT_MULTITHREADED);

	CoInitializeSecurity(
		nullptr, // TODO: "O:BAG:BAD:(A;;0x7;;;PS)(A;;0x3;;;SY)(A;;0x7;;;BA)(A;;0x3;;;AC)(A;;0x3;;;LS)(A;;0x3;;;NS)"
		-1,
		nullptr,
		nullptr,
		RPC_C_AUTHN_LEVEL_DEFAULT,
		RPC_C_IMP_LEVEL_IDENTIFY,
		NULL,
		EOAC_NONE,
		nullptr);

	if (!InitializeCriticalSectionAndSpinCount(&OutputCriticalSection, 0x00000400))
	{
		return -1;
	}

	bleAdvertisementWatcher = ref new Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher();
	bleAdvertisementWatcher->ScanningMode = Bluetooth::Advertisement::BluetoothLEScanningMode::Active;
	bleAdvertisementWatcher->Received += ref new Windows::Foundation::TypedEventHandler<Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher ^, Windows::Devices::Bluetooth::Advertisement::BluetoothLEAdvertisementReceivedEventArgs ^>(
		[](Bluetooth::Advertisement::BluetoothLEAdvertisementWatcher ^ watcher, Bluetooth::Advertisement::BluetoothLEAdvertisementReceivedEventArgs ^ eventArgs)
		{
			unsigned int index = -1;

			JsonObject ^ msg = ref new JsonObject();
			msg->Insert("_type", JsonValue::CreateStringValue("scanResult"));
			msg->Insert("bluetoothAddress", JsonValue::CreateStringValue(ref new String(formatBluetoothAddress(eventArgs->BluetoothAddress).c_str())));
			msg->Insert("rssi", JsonValue::CreateNumberValue(eventArgs->RawSignalStrengthInDBm));
			// TODO fix timestamp calculation
			msg->Insert("timestamp", JsonValue::CreateNumberValue((double)eventArgs->Timestamp.UniversalTime / 10000.0 + 11644480800000));
			msg->Insert("advType", JsonValue::CreateStringValue(eventArgs->AdvertisementType.ToString()));
			msg->Insert("localName", JsonValue::CreateStringValue(eventArgs->Advertisement->LocalName));

			auto manufacturerSections = eventArgs->Advertisement->ManufacturerData;
			if (manufacturerSections->Size > 0)
			{
				auto manufacturerData = manufacturerSections->GetAt(0);
				auto finalData = ref new JsonArray();
				auto rawMnData = manufacturerData->Data;
				uint8_t *prefix = uint16_t_union{manufacturerData->CompanyId}.bytes;
				std::vector<uint8_t> companyIdData = std::vector<uint8_t>{prefix, prefix + sizeof(uint16_t_union)};
				std::vector<uint8_t> mnData;
				auto dataReader = Windows::Storage::Streams::DataReader::FromBuffer(rawMnData);
				while (dataReader->UnconsumedBufferLength > 0)
				{
					auto byte = dataReader->ReadByte();
					mnData.push_back(byte);
				}
				for (auto &element : companyIdData)
				{
					finalData->Append(JsonValue::CreateNumberValue(element));
				};
				for (auto &element : mnData)
				{
					finalData->Append(JsonValue::CreateNumberValue(element));
				};
				msg->Insert("manufacturerData", finalData);
			}

			// Serialise the individual raw AD structures as arrays of bytes in JSON
			// The AD structures concatenated should contain the entire raw payload of the advertisement
			// The entire payload is sent as JSON just in case we need other stuff in the future
			auto adStructures = ref new JsonArray();
			for (auto &rawAdStructure : eventArgs->Advertisement->DataSections)
			{
				auto adStructure = ref new JsonObject();
				adStructure->Insert("type", JsonValue::CreateNumberValue(rawAdStructure->DataType));

				auto adData = ref new JsonArray();
				auto rawData = rawAdStructure->Data;

				auto dataReader = Windows::Storage::Streams::DataReader::FromBuffer(rawData);
				while (dataReader->UnconsumedBufferLength > 0)
				{
					auto byte = dataReader->ReadByte();
					adData->Append(JsonValue::CreateNumberValue(byte));
				}

				adStructure->Insert("data", adData);
				adStructures->Append(adStructure);
			}
			msg->Insert("adStructures", adStructures);

			JsonArray ^ serviceUuids = ref new JsonArray();
			for (unsigned int i = 0; i < eventArgs->Advertisement->ServiceUuids->Size; i++)
			{
				serviceUuids->Append(JsonValue::CreateStringValue(eventArgs->Advertisement->ServiceUuids->GetAt(i).ToString()));
			}
			msg->Insert("serviceUuids", serviceUuids);

			// TODO manfuacturer data / flags / data sections ?
			writeObject(msg);
		});

	// Added the ability to track the BLE Radio State
	auto getRadiosOperation = Radio::GetRadiosAsync();
	create_task(getRadiosOperation).then([](task<IVectorView<Radio ^> ^> asyncInfo)
										 {
			auto radios = asyncInfo.get();
			boolean haveBleRadio = false;
			for (Windows::Devices::Radios::Radio^ radio : radios)
			{
				if (radio->Kind == RadioKind::Bluetooth)
				{
					haveBleRadio = true;
					JsonObject^ msg = ref new JsonObject();
					msg->Insert("_type", JsonValue::CreateStringValue("ble_state"));
					msg->Insert("state", JsonValue::CreateStringValue(radio->State.ToString()));
					writeObject(msg);
					radio->StateChanged += ref new Windows::Foundation::TypedEventHandler<Windows::Devices::Radios::Radio^, Platform::Object^>(
						[](Windows::Devices::Radios::Radio^ sender, Platform::Object^ args)
						{
							JsonObject^ msg = ref new JsonObject();
							msg->Insert("_type", JsonValue::CreateStringValue("ble_state"));
							msg->Insert("state", JsonValue::CreateStringValue(sender->State.ToString()));
							writeObject(msg);
							
						}
					);
				}
			} });

	JsonObject ^ msg = ref new JsonObject();
	msg->Insert("_type", JsonValue::CreateStringValue("Start"));
	writeObject(msg);

	// Set STDIN / STDOUT to binary mode
	if ((_setmode(0, _O_BINARY) == -1) || (_setmode(1, _O_BINARY) == -1))
	{
		return -1;
	}

	stdext::cvt::wstring_convert<std::codecvt_utf8<wchar_t>> convert;
	try
	{
		while (!std::cin.eof())
		{
			unsigned int len = 0;
			std::cin.read(reinterpret_cast<char *>(&len), 4);

			if (len > 0)
			{
				char *msgBuf = new char[len];
				std::cin.read(msgBuf, len);
				String ^ jsonStr = ref new String(convert.from_bytes(msgBuf, msgBuf + len).c_str());
				delete[] msgBuf;
				JsonObject ^ json = JsonObject::Parse(jsonStr);
				processCommand(json);
			}
		}
	}
	catch (std::exception &e)
	{
		JsonObject ^ msg = ref new JsonObject();
		msg->Insert("_type", JsonValue::CreateStringValue("error"));
		std::string eReason = std::string(e.what());
		std::wstring wReason = std::wstring(eReason.begin(), eReason.end());
		msg->Insert("error", JsonValue::CreateStringValue(ref new String(wReason.c_str())));
		writeObject(msg);
	}

	DeleteCriticalSection(&OutputCriticalSection);

	return 0;
}
