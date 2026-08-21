/// Which mDNS backend advertises the OpenBikeControl controller service.
///
/// Per-service on purpose: the DirCon bridge and Click/Rouvy advertisements
/// stay on prop's in-process responder regardless (MyWhoosh's DirCon
/// discovery requires hostname == service name, prop e3e451c). Only the
/// `_openbikecontrol._tcp` / OBC-DirCon advertisement can be handed to the OS
/// responder, which makes same-host hostname resolution internal to Windows.
enum ObpMdnsBackend { platformDefault, osResponder }
