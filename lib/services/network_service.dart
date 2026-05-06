import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  final Connectivity _connectivity = Connectivity();

  Future<bool> isOnline() async {
    final List<ConnectivityResult> connectivityResult = await _connectivity.checkConnectivity();
    
    // Check if the device is connected to Mobile Data, WiFi, or Ethernet
    if (connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi) ||
        connectivityResult.contains(ConnectivityResult.ethernet)) {
      return true;
    }
    
    return false;
  }
}
