package com.navideck.universal_ble

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import android.Manifest
import android.annotation.SuppressLint

private const val TAG = "PermissionHandler"

/**
 * Handles Bluetooth-related permission requests for Android.
 * Automatically determines which permissions to request based on:
 * 1. Android version (SDK level)
 * 2. Permissions declared in AndroidManifest.xml
 */
class PermissionHandler(
    private val context: Context,
    private val activity: Activity,
    private val requestCode: Int,
) {
    private var permissionRequestCallback: ((Result<Unit>) -> Unit)? = null

    /**
     * Requests the required Bluetooth permissions based on the manifest and Android version.
     *
     * @param callback Called with the result of the permission request
     */
    fun requestPermissions(
        withFineLocation: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) {
        // Validate required permissions are declared in manifest
        val validationError = validateRequiredPermissions(withFineLocation)
        if (validationError != null) {
            callback(Result.failure(validationError))
            return
        }

        // Check which permissions are declared in manifest
        val permissionsToRequest = getRequiredPermissions(withFineLocation)

        if (permissionsToRequest.isEmpty()) {
            // All required permissions are already granted
            callback(Result.success(Unit))
            return
        }

        // Check if we already have a pending permission request
        if (permissionRequestCallback != null) {
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.OPERATION_IN_PROGRESS,
                        "Permission request already in progress"
                    )
                )
            )
            return
        }

        permissionRequestCallback = callback
        ActivityCompat.requestPermissions(
            activity,
            permissionsToRequest.toTypedArray(),
            requestCode
        )
    }

    /**
     * Handles permission request results.
     * Should be called from onRequestPermissionsResult in the Activity.
     *
     * @param requestCode The request code from the permission request
     * @param permissions The permissions that were requested
     * @param grantResults The grant results for each permission
     * @return true if the request code matches and the result was handled, false otherwise
     */
    fun handlePermissionResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != this.requestCode) {
            return false
        }

        val callback = permissionRequestCallback ?: return false
        permissionRequestCallback = null

        val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (allGranted) {
            callback(Result.success(Unit))
        } else {
            val deniedPermissions = permissions.filterIndexed { index, _ ->
                grantResults[index] != PackageManager.PERMISSION_GRANTED
            }
            callback(
                Result.failure(
                    createFlutterError(
                        UniversalBleErrorCode.FAILED,
                        "Permissions denied: ${deniedPermissions.joinToString(", ")}"
                    )
                )
            )
        }
        return true
    }


    /**
     * Determines which permissions need to be requested based on:
     * 1. Android version
     * 2. Permissions declared in AndroidManifest.xml
     * 3. Whether user wants to request location permission (withFineLocation parameter)
     *
     * @param withFineLocation If true, request location permission when needed.
     *                         On Android 11 and below, location is always requested if declared
     *                         (it's mandatory for BLE scanning).
     *
     * Returns a list of permissions that need to be requested (excluding already granted ones)
     */
    private fun getRequiredPermissions(withFineLocation: Boolean): List<String> {
        val permissionsToRequest = mutableListOf<String>()
        // Android 12+ (API 31+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // BLUETOOTH_SCAN is mandatory
            if (!hasPermissionGranted(Manifest.permission.BLUETOOTH_SCAN)) {
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_SCAN)
            }
            // BLUETOOTH_CONNECT is mandatory
            if (!hasPermissionGranted(Manifest.permission.BLUETOOTH_CONNECT)) {
                permissionsToRequest.add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            // Location permission is optional - only request if user wants it
            if (withFineLocation) {
                // Prefer ACCESS_FINE_LOCATION over ACCESS_COARSE_LOCATION
                permissionsToRequest.addAll(getLocationPermissionsToAsk())
            }
        } else {
            // Android 11 and below
            permissionsToRequest.add(Manifest.permission.BLUETOOTH)
            // Location permission is MANDATORY
            // Prefer ACCESS_FINE_LOCATION over ACCESS_COARSE_LOCATION
            permissionsToRequest.addAll(getLocationPermissionsToAsk())
        }
        return permissionsToRequest
    }

    private fun getLocationPermissionsToAsk(): List<String> {
        val hasDeclaredFineLocation =
            hasPermissionInManifest(Manifest.permission.ACCESS_FINE_LOCATION)
        val hasDeclaredCoarseLocation =
            hasPermissionInManifest(Manifest.permission.ACCESS_COARSE_LOCATION)
        val permissionsToRequest = mutableListOf<String>()
        if (hasDeclaredFineLocation) {
            if (!hasPermissionGranted(Manifest.permission.ACCESS_FINE_LOCATION)) {
                permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
            }
        } else if (hasDeclaredCoarseLocation) {
            if (!hasPermissionGranted(Manifest.permission.ACCESS_COARSE_LOCATION)) {
                permissionsToRequest.add(Manifest.permission.ACCESS_COARSE_LOCATION)
            }
        }
        return permissionsToRequest
    }

    /**
     * Checks if a permission is declared in AndroidManifest.xml
     */
    private fun hasPermissionInManifest(permission: String): Boolean {
        return try {
            val packageInfo = context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_PERMISSIONS
            )
            packageInfo.requestedPermissions?.contains(permission) == true
        } catch (e: Exception) {
            Log.e(TAG, "Error checking permission in manifest: ${e.message}")
            false
        }
    }

    private fun hasPermissionGranted(permission: String): Boolean {
        return ActivityCompat.checkSelfPermission(
            context,
            permission
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Validates that all required permissions are declared in AndroidManifest.xml.
     * Returns an error if any required permission is missing.
     *
     * @param withFineLocation Whether location permission should be requested
     * @return FlutterError if validation fails, null if all required permissions are declared
     */
    private fun validateRequiredPermissions(withFineLocation: Boolean): FlutterError? {
        val sdkInt = Build.VERSION.SDK_INT
        val missingPermissions = mutableListOf<String>()

        val hasDeclaredFineLocation =
            hasPermissionInManifest(Manifest.permission.ACCESS_FINE_LOCATION)
        val hasDeclaredCoarseLocation =
            hasPermissionInManifest(Manifest.permission.ACCESS_COARSE_LOCATION)
        val hasDeclaredLocationPermission = hasDeclaredFineLocation || hasDeclaredCoarseLocation

        // Android 12+ (API 31+)
        @SuppressLint("InlinedApi")
        if (sdkInt >= Build.VERSION_CODES.S) {
            // BLUETOOTH_SCAN is mandatory on Android 12+
            if (!hasPermissionInManifest(Manifest.permission.BLUETOOTH_SCAN)) {
                missingPermissions.add(Manifest.permission.BLUETOOTH_SCAN)
            }

            // BLUETOOTH_CONNECT is mandatory on Android 12+
            if (!hasPermissionInManifest(Manifest.permission.BLUETOOTH_CONNECT)) {
                missingPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
            }

            // Location permission is optional on Android 12+ (depends on neverForLocation and withFineLocation)
            // Only validate if it's actually needed
            if (withFineLocation && !hasDeclaredLocationPermission) {
                missingPermissions.add("${Manifest.permission.ACCESS_FINE_LOCATION} or ${Manifest.permission.ACCESS_COARSE_LOCATION}")
            }
        } else {
            // Android 11 and below
            if (!hasPermissionInManifest(Manifest.permission.BLUETOOTH)) {
                missingPermissions.add(Manifest.permission.BLUETOOTH)
            }
            // Android 11 and below, Location permission is MANDATORY for BLE scanning
            if (!hasDeclaredLocationPermission) {
                missingPermissions.add("${Manifest.permission.ACCESS_FINE_LOCATION} or ${Manifest.permission.ACCESS_COARSE_LOCATION}")
            }
        }

        if (missingPermissions.isNotEmpty()) {
            return createFlutterError(
                UniversalBleErrorCode.FAILED,
                "Required permissions are not declared in AndroidManifest.xml",
                "Missing permissions: ${missingPermissions.joinToString(", ")}. " +
                        "Please add these permissions to your AndroidManifest.xml file. " +
                        "See README.md for more information."
            )
        }
        return null
    }
}
