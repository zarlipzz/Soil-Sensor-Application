package com.soil.sensor.soil_app

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val connectivity by lazy {
        getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
    }
    private var networkChannel: EventChannel? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        networkChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.soil.sensor.soil_app/network",
        ).apply {
            setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    stopMonitoringNetwork()
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) = emit(network, false)

                        override fun onCapabilitiesChanged(
                            network: Network,
                            capabilities: NetworkCapabilities,
                        ) = emit(
                            network,
                            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
                        )

                        override fun onLost(network: Network) = emit(null, false)

                        private fun emit(network: Network?, hasInternet: Boolean) {
                            runOnUiThread {
                                if (networkCallback === this) {
                                    events.success(mapOf(
                                        "network" to network?.networkHandle,
                                        "hasInternet" to hasInternet,
                                    ))
                                }
                            }
                        }
                    }
                    networkCallback = callback
                    try {
                        connectivity.registerDefaultNetworkCallback(callback)
                    } catch (_: RuntimeException) {
                        networkCallback = null
                        events.error("network_monitor", "Could not monitor network changes", null)
                    }
                }

                override fun onCancel(arguments: Any?) = stopMonitoringNetwork()
            })
        }
    }

    private fun stopMonitoringNetwork() {
        val callback = networkCallback ?: return
        networkCallback = null
        connectivity.unregisterNetworkCallback(callback)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        stopMonitoringNetwork()
        networkChannel?.setStreamHandler(null)
        networkChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
