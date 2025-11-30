package com.accuniq.accuniq_flutter_demo

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.accuniq.ble_pairing"
    private var pairingChannel: MethodChannel? = null
    
    private var pairingReceiver: BroadcastReceiver? = null
    private val knownDevices = mutableMapOf<String, String>() // Map<address, pin>
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register pairing receiver immediately to catch all pairing requests
        registerGlobalPairingReceiver()
        
        pairingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        pairingChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pairDevice" -> {
                    val address = call.argument<String>("address")
                    val pin = call.argument<String>("pin")
                    if (address != null && pin != null) {
                        // Store device PIN for future pairing requests
                        knownDevices[address.uppercase()] = pin
                        pairDeviceWithPin(address, pin, result)
                    } else {
                        result.error("INVALID_ARGUMENT", "Address and PIN are required", null)
                    }
                }
                "isPaired" -> {
                    val address = call.argument<String>("address")
                    if (address != null) {
                        result.success(isDevicePaired(address))
                    } else {
                        result.error("INVALID_ARGUMENT", "Address is required", null)
                    }
                }
                "registerDevicePin" -> {
                    // Register device PIN for automatic pairing
                    val address = call.argument<String>("address")
                    val pin = call.argument<String>("pin")
                    if (address != null && pin != null) {
                        knownDevices[address.uppercase()] = pin
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Address and PIN are required", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    /// Register global pairing receiver to automatically handle pairing requests
    private fun registerGlobalPairingReceiver() {
        if (pairingReceiver != null) {
            Log.d("MainActivity", "Global pairing receiver already registered")
            return // Already registered
        }
        
        pairingReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                Log.d("MainActivity", "BroadcastReceiver received action: ${intent.action}")
                when (intent.action) {
                    BluetoothDevice.ACTION_PAIRING_REQUEST -> {
                        Log.d("MainActivity", "ACTION_PAIRING_REQUEST received")
                        val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                        device?.let { dev ->
                            val address = dev.address.uppercase()
                            Log.d("MainActivity", "Pairing request for device: $address")
                            val pin = knownDevices[address]
                            
                            if (pin != null) {
                                Log.d("MainActivity", "Auto-handling pairing request for $address with PIN")
                                try {
                                    // Try to get pairing variant (may not be available in all Android versions)
                                    var pairingVariant = 0
                                    try {
                                        pairingVariant = intent.getIntExtra(
                                            BluetoothDevice.EXTRA_PAIRING_VARIANT,
                                            0
                                        )
                                        Log.d("MainActivity", "Pairing variant: $pairingVariant")
                                    } catch (e: Exception) {
                                        Log.d("MainActivity", "Could not get pairing variant: ${e.message}")
                                    }
                                    
                                    // Try PIN pairing first (most common)
                                    // Use reflection to bypass permission check if possible
                                    try {
                                        val pairingPin = pin.toByteArray(Charsets.UTF_8)
                                        
                                        // Try using reflection to set PIN (may work on some devices)
                                        try {
                                            val setPinMethod = dev.javaClass.getMethod("setPin", ByteArray::class.java)
                                            setPinMethod.invoke(dev, pairingPin)
                                            Log.d("MainActivity", "✅ PIN set via reflection: $address")
                                        } catch (re: Exception) {
                                            // Fallback to normal method
                                            dev.setPin(pairingPin)
                                            Log.d("MainActivity", "✅ PIN set via normal method: $address")
                                        }
                                        
                                        // Try using reflection to confirm pairing
                                        try {
                                            val confirmMethod = dev.javaClass.getMethod("setPairingConfirmation", Boolean::class.java)
                                            confirmMethod.invoke(dev, true)
                                            Log.d("MainActivity", "✅ Pairing confirmed via reflection: $address")
                                        } catch (re: Exception) {
                                            // Fallback to normal method
                                            dev.setPairingConfirmation(true)
                                            Log.d("MainActivity", "✅ Pairing confirmed via normal method: $address")
                                        }
                                        
                                        Log.d("MainActivity", "✅ PIN set and confirmed automatically: $address (variant=$pairingVariant)")
                                    } catch (e: Exception) {
                                        // If setPin fails, try just confirming
                                        Log.d("MainActivity", "setPin failed: ${e.message}, trying confirmation only")
                                        try {
                                            // Try reflection for confirmation only
                                            try {
                                                val confirmMethod = dev.javaClass.getMethod("setPairingConfirmation", Boolean::class.java)
                                                confirmMethod.invoke(dev, true)
                                                Log.d("MainActivity", "✅ Pairing confirmed via reflection (PIN failed): $address")
                                            } catch (re: Exception) {
                                                dev.setPairingConfirmation(true)
                                                Log.d("MainActivity", "✅ Pairing confirmed (PIN failed): $address")
                                            }
                                        } catch (e2: Exception) {
                                            Log.e("MainActivity", "❌ Failed to handle pairing: ${e2.message}")
                                            Log.e("MainActivity", "⚠️ User may need to manually pair device: $address")
                                        }
                                    }
                                } catch (e: Exception) {
                                    Log.e("MainActivity", "❌ Error auto-handling pairing: ${e.message}", e)
                                }
                            } else {
                                Log.d("MainActivity", "⚠️ Pairing request for unknown device (no PIN): $address")
                                Log.d("MainActivity", "Known devices: ${knownDevices.keys}")
                            }
                        } ?: Log.e("MainActivity", "Device is null in pairing request")
                    }
                    else -> {
                        Log.d("MainActivity", "Received other action: ${intent.action}")
                    }
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        
        try {
            registerReceiver(pairingReceiver, filter)
            Log.d("MainActivity", "✅ Global pairing receiver registered successfully")
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Failed to register pairing receiver: ${e.message}", e)
        }
    }
    
    private fun isDevicePaired(address: String): Boolean {
        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
        if (bluetoothAdapter == null) {
            return false
        }
        
        val pairedDevices = bluetoothAdapter.bondedDevices
        for (device in pairedDevices) {
            if (device.address.equals(address, ignoreCase = true)) {
                return true
            }
        }
        return false
    }
    
    private fun pairDeviceWithPin(address: String, pin: String, result: MethodChannel.Result) {
        try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            if (bluetoothAdapter == null) {
                result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth adapter not available", null)
                return
            }
            
            if (!bluetoothAdapter.isEnabled) {
                result.error("BLUETOOTH_DISABLED", "Bluetooth is disabled", null)
                return
            }
            
            // Store PIN for automatic pairing
            knownDevices[address.uppercase()] = pin
            
            // Check if already paired
            if (isDevicePaired(address)) {
                result.success(true)
                return
            }
            
            val device = bluetoothAdapter.getRemoteDevice(address)
            if (device == null) {
                result.error("DEVICE_NOT_FOUND", "Device not found: $address", null)
                return
            }
            
            // Register temporary receiver for pairing completion
            var tempReceiver: BroadcastReceiver? = null
            tempReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    when (intent.action) {
                        BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                            val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                            if (device?.address?.equals(address, ignoreCase = true) == true) {
                                val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.BOND_NONE)
                                when (bondState) {
                                    BluetoothDevice.BOND_BONDED -> {
                                        Log.d("MainActivity", "Device paired successfully: $address")
                                        unregisterReceiver(tempReceiver)
                                        result.success(true)
                                    }
                                    BluetoothDevice.BOND_NONE -> {
                                        if (device.bondState == BluetoothDevice.BOND_NONE) {
                                            Log.d("MainActivity", "Pairing failed or cancelled: $address")
                                            unregisterReceiver(tempReceiver)
                                            result.error("PAIRING_FAILED", "Pairing failed", null)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
            }
            
            registerReceiver(tempReceiver, filter)
            
            // Start pairing
            Log.d("MainActivity", "Starting pairing with device: $address")
            if (device.bondState == BluetoothDevice.BOND_NONE) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    device.createBond()
                } else {
                    @Suppress("DEPRECATION")
                    device.createBond()
                }
            }
            
            // Set timeout
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!isDevicePaired(address)) {
                    unregisterReceiver(tempReceiver)
                    result.error("PAIRING_TIMEOUT", "Pairing timeout", null)
                }
            }, 30000) // 30 seconds timeout
            
        } catch (e: Exception) {
            Log.e("MainActivity", "Error pairing device: ${e.message}", e)
            result.error("PAIRING_ERROR", e.message, null)
        }
    }
    
    private fun unregisterPairingReceiver() {
        pairingReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                Log.e("MainActivity", "Error unregistering receiver: ${e.message}", e)
            }
            pairingReceiver = null
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        unregisterPairingReceiver()
    }
}
