package com.sudosoc.sudosend

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.NetworkInfo
import android.net.wifi.WpsInfo
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pDeviceList
import android.net.wifi.p2p.WifiP2pInfo
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Phone-to-phone Wi-Fi Direct. Two Android phones form a private Wi-Fi link
 * with no router and no hotspot; both usually stay on their normal Wi-Fi.
 * Once the group is up, SUDOSEND's normal discovery and encrypted transport
 * run over it unchanged (the group owner is always 192.168.49.1).
 *
 * SUDOSEND phones advertise a DNS-SD service ("_sudosend._tcp") inside Wi-Fi
 * Direct so the list can show which nearby devices actually run the app.
 * That record is only a hint — identity is still proven by the handshake.
 */
@SuppressLint("MissingPermission") // permission is requested from Dart before every call
object WifiDirect {
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private val main = Handler(Looper.getMainLooper())

    private var enabled = false
    private var scanning = false
    private var peers: List<WifiP2pDevice> = emptyList()
    /** deviceAddress → SUDOSEND device name, learned from service discovery. */
    private val sudosend = HashMap<String, String>()
    private var serviceInfo: WifiP2pDnsSdServiceInfo? = null
    private var serviceRequest: WifiP2pDnsSdServiceRequest? = null
    private var lastConnection: Map<String, Any?> = mapOf("type" to "connection", "connected" to false)

    private val rescan = object : Runnable {
        override fun run() {
            if (!scanning) return
            discoverNow()
            // Peer and service discovery both time out after ~2 minutes and
            // many vendors stop much sooner; poke them regularly while visible.
            main.postDelayed(this, 20_000)
        }
    }

    private fun ensure(ctx: Context): Boolean {
        if (manager != null) return true
        val m = ctx.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager ?: return false
        manager = m
        channel = m.initialize(ctx, Looper.getMainLooper()) {
            // Framework dropped the channel (e.g. Wi-Fi restarted): re-create on next call.
            manager = null
            channel = null
        }
        return channel != null
    }

    /** Registers for Wi-Fi Direct broadcasts. Cheap; safe to call repeatedly. */
    fun attach(ctx: Context): Boolean {
        if (!ensure(ctx)) return false
        if (receiver != null) return true
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                        enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        Bridge.emit("onP2p", mapOf("type" to "state", "enabled" to enabled))
                    }
                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> requestPeers()
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        @Suppress("DEPRECATION")
                        val net = intent.getParcelableExtra<NetworkInfo>(WifiP2pManager.EXTRA_NETWORK_INFO)
                        @Suppress("DEPRECATION")
                        if (net?.isConnected == true) requestConnection() else emitDisconnected()
                    }
                }
            }
        }
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            ctx.registerReceiver(r, filter)
        }
        receiver = r
        return true
    }

    /** Publishes "this phone runs SUDOSEND" so scanners can label it. */
    fun advertise(ctx: Context, name: String, fp: String) {
        if (!attach(ctx)) return
        val m = manager ?: return
        val ch = channel ?: return
        serviceInfo?.let { m.removeLocalService(ch, it, null) }
        val record = mapOf("n" to name.take(40), "fp" to fp.take(8), "v" to "1")
        val info = WifiP2pDnsSdServiceInfo.newInstance("SUDOSEND", "_sudosend._tcp", record)
        serviceInfo = info
        try {
            m.addLocalService(ch, info, null)
        } catch (_: SecurityException) {
        }
    }

    fun startScan(ctx: Context, result: MethodChannel.Result) {
        if (!attach(ctx)) {
            result.error("unsupported", "unsupported", null)
            return
        }
        val m = manager!!
        val ch = channel!!
        m.setDnsSdResponseListeners(
            ch,
            { _, _, _ -> },
            { _, txt, device ->
                val n = txt["n"]
                if (n != null && device != null) {
                    sudosend[device.deviceAddress] = n
                    emitPeers()
                }
            },
        )
        if (serviceRequest == null) {
            val req = WifiP2pDnsSdServiceRequest.newInstance("_sudosend._tcp")
            serviceRequest = req
            m.addServiceRequest(ch, req, null)
        }
        scanning = true
        main.removeCallbacks(rescan)
        main.post(rescan)
        // Report the current link, if any, so a freshly opened screen is right.
        Bridge.emit("onP2p", lastConnection)
        result.success(true)
    }

    private fun discoverNow() {
        val m = manager ?: return
        val ch = channel ?: return
        try {
            m.discoverPeers(ch, object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    // Service discovery after peer discovery: several vendors
                    // cancel one when the other starts at the same moment.
                    main.postDelayed({
                        try {
                            if (scanning) m.discoverServices(ch, null)
                        } catch (_: SecurityException) {
                        }
                    }, 1500)
                }

                override fun onFailure(reason: Int) {
                    Bridge.emit("onP2p", mapOf("type" to "error", "reason" to reasonText(reason)))
                }
            })
        } catch (e: SecurityException) {
            Bridge.emit("onP2p", mapOf("type" to "error", "reason" to "permission"))
        }
    }

    fun stopScan() {
        scanning = false
        main.removeCallbacks(rescan)
        val m = manager ?: return
        val ch = channel ?: return
        m.stopPeerDiscovery(ch, null)
        serviceRequest?.let { m.removeServiceRequest(ch, it, null) }
        serviceRequest = null
    }

    fun connect(address: String, result: MethodChannel.Result) {
        val m = manager
        val ch = channel
        if (m == null || ch == null) {
            result.error("unsupported", "unsupported", null)
            return
        }
        val config = WifiP2pConfig().apply {
            deviceAddress = address
            wps.setup = WpsInfo.PBC
            // The phone that starts the link hosts it (gets 192.168.49.1).
            groupOwnerIntent = 15
        }
        fun attempt(retry: Boolean) {
            try {
                m.connect(ch, config, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        result.success(true)
                    }

                    override fun onFailure(reason: Int) {
                        if (retry && reason == WifiP2pManager.BUSY) {
                            // A stale group or pending invite: clear it and try once more.
                            m.cancelConnect(ch, null)
                            m.removeGroup(ch, object : WifiP2pManager.ActionListener {
                                override fun onSuccess() {
                                    main.postDelayed({ attempt(false) }, 800)
                                }

                                override fun onFailure(r: Int) {
                                    main.postDelayed({ attempt(false) }, 800)
                                }
                            })
                        } else {
                            result.error("failed", reasonText(reason), null)
                        }
                    }
                })
            } catch (e: SecurityException) {
                result.error("permission", "permission", null)
            }
        }
        attempt(true)
    }

    fun disconnect(result: MethodChannel.Result?) {
        val m = manager
        val ch = channel
        if (m == null || ch == null) {
            result?.success(true)
            return
        }
        m.cancelConnect(ch, null)
        m.removeGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                result?.success(true)
            }

            override fun onFailure(reason: Int) {
                result?.success(false)
            }
        })
    }

    private fun requestPeers() {
        val m = manager ?: return
        val ch = channel ?: return
        try {
            m.requestPeers(ch) { list: WifiP2pDeviceList? ->
                peers = list?.deviceList?.toList() ?: emptyList()
                emitPeers()
            }
        } catch (_: SecurityException) {
        }
    }

    private fun emitPeers() {
        val out = peers.map { d ->
            mapOf(
                "name" to (d.deviceName ?: ""),
                "address" to d.deviceAddress,
                "status" to d.status, // 0 connected, 1 invited, 2 failed, 3 available, 4 unavailable
                "sudosend" to sudosend[d.deviceAddress],
            )
        }
        Bridge.emit("onP2p", mapOf("type" to "peers", "peers" to out))
    }

    private fun requestConnection() {
        val m = manager ?: return
        val ch = channel ?: return
        m.requestConnectionInfo(ch) { info: WifiP2pInfo? ->
            if (info == null || !info.groupFormed) {
                emitDisconnected()
                return@requestConnectionInfo
            }
            val base = mapOf(
                "type" to "connection",
                "connected" to true,
                "owner" to info.isGroupOwner,
                "ownerAddress" to info.groupOwnerAddress?.hostAddress,
            )
            try {
                m.requestGroupInfo(ch) { group ->
                    val other = if (info.isGroupOwner) {
                        group?.clientList?.firstOrNull()?.deviceName
                    } else {
                        group?.owner?.deviceName
                    }
                    lastConnection = base + mapOf("peerName" to other, "clients" to (group?.clientList?.size ?: 0))
                    Bridge.emit("onP2p", lastConnection)
                }
            } catch (_: SecurityException) {
                lastConnection = base
                Bridge.emit("onP2p", lastConnection)
            }
        }
    }

    private fun emitDisconnected() {
        lastConnection = mapOf("type" to "connection", "connected" to false)
        Bridge.emit("onP2p", lastConnection)
    }

    private fun reasonText(reason: Int): String = when (reason) {
        WifiP2pManager.P2P_UNSUPPORTED -> "unsupported"
        WifiP2pManager.BUSY -> "busy"
        else -> "error"
    }

    fun detach(ctx: Context) {
        stopScan()
        receiver?.let {
            try {
                ctx.unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        receiver = null
        val m = manager
        val ch = channel
        if (m != null && ch != null) serviceInfo?.let { m.removeLocalService(ch, it, null) }
        serviceInfo = null
    }
}
