# BleServer

This repository contains a modified version of [web-bluetooth-polyfill](https://github.com/urish/web-bluetooth-polyfill) , To make it work with Flutter Windows

To use this repository, build the BLEServer executable (BLEServer.vcxproj) using visual studio or msbuild and copy the executable into `lib/assets` folder.

If you have any trouble with visual studio not being able to find platform.winrt, then make sure that the Additional #using directories is correct. The setting can be found in the BLEServer project under C/C++ general settings.
For more Troubleshooting , Checkout [web-bluetooth-polyfill](https://github.com/urish/web-bluetooth-polyfill)
