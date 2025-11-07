import 'package:flutter/services.dart';
import 'package:universal_ble/src/universal_ble_pigeon/universal_ble.g.dart';
import 'package:universal_ble/universal_ble.dart';

// TODO: improve this..
extension UniversalBleErrorMapper<T> on Future<T> {
  Future<T> toUniversalBleError() {
    return catchError((error, stack) {
      if (error is UniversalBleException) {
        throw error;
      }
      if (error is PlatformException) {
        throw UniversalBleException.fromPlatformException(error);
      }
      if (error is String) {
        throw ErrorMapper.fromStringCode(error);
      }
      if (error is int) {
        throw ErrorMapper.fromNumericCode(error);
      }
      throw UniversalBleException.fromError(error);
    });
  }
}

/// Maps platform-specific error codes and messages to unified error codes
class ErrorMapper {
  /// Maps a PlatformException to a UniversalBleErrorCode
  static UniversalBleErrorCode fromPlatformException(PlatformException error) {
    final code = error.code;
    final message = error.message ?? '';

    // Try to map by code first
    final codeMapping = _mapErrorCode(code);
    if (codeMapping != null) {
      return codeMapping;
    }

    // Try to map by message
    final messageMapping = _mapErrorMessage(message);
    if (messageMapping != null) {
      return messageMapping;
    }

    // Default to unknown error
    return UniversalBleErrorCode.unknownError;
  }

  /// Maps a string error code to UniversalBleErrorCode
  static UniversalBleErrorCode fromStringCode(String code, {String? message}) {
    // Try code mapping first
    final codeMapping = _mapErrorCode(code);
    if (codeMapping != null) {
      return codeMapping;
    }

    // Try message mapping if provided
    if (message != null) {
      final messageMapping = _mapErrorMessage(message);
      if (messageMapping != null) {
        return messageMapping;
      }
    }

    return UniversalBleErrorCode.unknownError;
  }

  static UniversalBleErrorCode fromNumericCode(int code) =>
      _mapNumericErrorCode(code);

  /// Maps error code string to UniversalBleErrorCode
  static UniversalBleErrorCode? _mapErrorCode(String code) {
    switch (code.toLowerCase()) {
      // General errors
      case 'notsupported':
      case 'not_supported':
        return UniversalBleErrorCode.notSupported;
      case 'notimplemented':
      case 'not_implemented':
        return UniversalBleErrorCode.notImplemented;
      case 'channel-error':
      case 'channelerror':
        return UniversalBleErrorCode.channelError;
      case 'failed':
        return UniversalBleErrorCode.failed;
      // Bluetooth availability
      case 'bluetoothnotavailable':
      case 'bluetooth_not_available':
        return UniversalBleErrorCode.bluetoothNotAvailable;
      case 'bluetoothnotenabled':
      case 'bluetooth_not_enabled':
        return UniversalBleErrorCode.bluetoothNotEnabled;
      case 'bluetoothnotallowed':
      case 'bluetooth_not_allowed':
        return UniversalBleErrorCode.bluetoothNotAllowed;
      case 'bluetoothunauthorized':
      case 'bluetooth_unauthorized':
        return UniversalBleErrorCode.bluetoothUnauthorized;

      // Connection errors
      case 'devicedisconnected':
      case 'device_disconnected':
        return UniversalBleErrorCode.deviceDisconnected;
      case 'connectiontimeout':
      case 'connection_timeout':
        return UniversalBleErrorCode.connectionTimeout;
      case 'connectionfailed':
      case 'connection_failed':
        return UniversalBleErrorCode.connectionFailed;
      case 'connectionrejected':
      case 'connection_rejected':
        return UniversalBleErrorCode.connectionRejected;
      case 'connecting':
      case 'connectioninprogress':
      case 'connection_in_progress':
        return UniversalBleErrorCode.connectionInProgress;
      case 'connectionterminated':
      case 'connection_terminated':
        return UniversalBleErrorCode.connectionTerminated;

      // Device/Service/Characteristic errors
      case 'illegalargument':
      case 'illegal_argument':
        return UniversalBleErrorCode.illegalArgument;
      case 'devicenotfound':
      case 'device_not_found':
        return UniversalBleErrorCode.deviceNotFound;
      case 'servicenotfound':
      case 'service_not_found':
        return UniversalBleErrorCode.serviceNotFound;
      case 'characteristicnotfound':
      case 'characteristic_not_found':
        return UniversalBleErrorCode.characteristicNotFound;
      case 'invalidserviceuuid':
      case 'invalid_service_uuid':
        return UniversalBleErrorCode.invalidServiceUuid;
      case 'invalidcharacteristicuuid':
      case 'invalid_characteristic_uuid':
        return UniversalBleErrorCode.invalidCharacteristicUuid;

      // Operation errors
      case 'readfailed':
      case 'read_failed':
        return UniversalBleErrorCode.readFailed;
      case 'writefailed':
      case 'write_failed':
      case 'writeerror':
      case 'write_error':
        return UniversalBleErrorCode.writeFailed;
      case 'invalidaction':
      case 'invalid_action':
        return UniversalBleErrorCode.invalidAction;
      case 'operationnotsupported':
      case 'operation_not_supported':
        return UniversalBleErrorCode.operationNotSupported;
      case 'operationtimeout':
      case 'operation_timeout':
        return UniversalBleErrorCode.operationTimeout;
      case 'operationcancelled':
      case 'operation_cancelled':
        return UniversalBleErrorCode.operationCancelled;
      case 'inprogress':
      case 'alreadyinprogress':
      case 'already_in_progress':
        return UniversalBleErrorCode.operationInProgress;

      // Pairing errors
      case 'notpaired':
      case 'not_paired':
        return UniversalBleErrorCode.notPaired;
      case 'notpairable':
      case 'not_pairable':
        return UniversalBleErrorCode.notPairable;
      case 'alreadypaired':
      case 'already_paired':
        return UniversalBleErrorCode.alreadyPaired;
      case 'pairingfailed':
      case 'pairing_failed':
        return UniversalBleErrorCode.pairingFailed;
      case 'pairingcancelled':
      case 'pairing_cancelled':
        return UniversalBleErrorCode.pairingCancelled;
      case 'pairingtimeout':
      case 'pairing_timeout':
        return UniversalBleErrorCode.pairingTimeout;
      case 'pairingnotallowed':
      case 'pairing_not_allowed':
        return UniversalBleErrorCode.pairingNotAllowed;
      case 'authenticationfailure':
      case 'authentication_failure':
        return UniversalBleErrorCode.authenticationFailure;
      // Consolidated: authenticationTimeout and authenticationNotAllowed -> authenticationFailure
      case 'authenticationtimeout':
      case 'authentication_timeout':
      case 'authenticationnotallowed':
      case 'authentication_not_allowed':
        return UniversalBleErrorCode.authenticationFailure;
      // Consolidated: hardwareFailure, tooManyConnections, notReadyToPair, etc. -> pairingFailed
      case 'hardwarefailure':
      case 'hardware_failure':
      case 'toomanyconnections':
      case 'too_many_connections':
      case 'notreadytopair':
      case 'not_ready_to_pair':
      case 'nonsupportedprofiles':
      case 'no_supported_profiles':
      case 'invalidceremonydata':
      case 'invalid_ceremony_data':
      case 'requiredhandlernotregistered':
      case 'required_handler_not_registered':
      case 'rejectedbyhandler':
      case 'rejected_by_handler':
      case 'remotedevicehasassociation':
      case 'remote_device_has_association':
        return UniversalBleErrorCode.pairingFailed;
      case 'protectionlevelcouldnotbemet':
      case 'protection_level_could_not_be_met':
        return UniversalBleErrorCode.protectionLevelNotMet;

      // Unpairing errors
      case 'unpairingfailed':
      case 'unpairing_failed':
        return UniversalBleErrorCode.unpairingFailed;
      case 'alreadyunpaired':
      case 'already_unpaired':
        return UniversalBleErrorCode.alreadyUnpaired;
      case 'accessdenied':
      case 'access_denied':
        return UniversalBleErrorCode.accessDenied;

      // Scan errors - all consolidated to scanFailed
      case 'scan_failed_already_started':
      case 'scanfailedalreadystarted':
      case 'scan_failed_application_registration_failed':
      case 'scanfailedapplicationregistrationfailed':
      case 'scan_failed_feature_unsupported':
      case 'scanfailedfeatureunsupported':
      case 'scan_failed_internal_error':
      case 'scanfailedinternalerror':
      case 'scan_failed_out_of_hardware_resources':
      case 'scanfailedoutofhardwareresources':
      case 'scan_failed_scanning_too_frequently':
      case 'scanfailedscanningtoofrequently':
        return UniversalBleErrorCode.scanFailed;
      case 'stoppingscaninprogress':
      case 'stopping_scan_in_progress':
        return UniversalBleErrorCode.stoppingScanInProgress;

      // GATT errors - all consolidated to common errors
      case 'gatt_failure':
      case 'gattfailure':
      case 'unreachable':
      case 'protocolerror':
      case 'protocol_error':
      case 'gattunreachable':
      case 'gatt_protocol_error':
      case 'gatt_unlikely':
      case 'gattunlikely':
      case 'gatt_insufficient_resources':
      case 'gattinsufficientresources':
        return UniversalBleErrorCode.failed;
      // Consolidated: gattReadNotPermitted -> readNotPermitted
      case 'gatt_read_not_permitted':
      case 'gattreadnotpermitted':
        return UniversalBleErrorCode.readNotPermitted;
      // Consolidated: gattWriteNotPermitted -> writeNotPermitted
      case 'gatt_write_not_permitted':
      case 'gattwritenotpermitted':
        return UniversalBleErrorCode.writeNotPermitted;
      // Consolidated: gattInsufficient* -> insufficient*
      case 'gatt_insufficient_authentication':
      case 'gattinsufficientauthentication':
        return UniversalBleErrorCode.insufficientAuthentication;
      case 'gatt_insufficient_authorization':
      case 'gattinsufficientauthorization':
        return UniversalBleErrorCode.insufficientAuthorization;
      case 'gatt_insufficient_encryption':
      case 'gattinsufficientencryption':
        return UniversalBleErrorCode.insufficientEncryption;
      case 'gatt_insufficient_key_size':
      case 'gattinsufficientkeysize':
        return UniversalBleErrorCode.insufficientKeySize;
      // Consolidated: gattRequestNotSupported -> operationNotSupported
      case 'gatt_request_not_supported':
      case 'gattrequestnotsupported':
        return UniversalBleErrorCode.operationNotSupported;
      // Consolidated: gattInvalid* -> invalid*
      case 'gatt_invalid_offset':
      case 'gattinvalidoffset':
        return UniversalBleErrorCode.invalidOffset;
      case 'gatt_invalid_attribute_length':
      case 'gattinvalidattributelength':
        return UniversalBleErrorCode.invalidAttributeLength;
      // Consolidated: gattConnectionCongested -> connectionFailed
      case 'gatt_connection_congested':
      case 'gattconnectioncongested':
        return UniversalBleErrorCode.connectionFailed;
      case 'gatt_invalid_handle':
      case 'gattinvalidhandle':
        return UniversalBleErrorCode.invalidHandle;
      case 'gatt_invalid_pdu':
      case 'gattinvalidpdu':
        return UniversalBleErrorCode.invalidPdu;
      // Consolidated: gattPrepareQueueFull -> operationInProgress
      case 'gatt_prepare_queue_full':
      case 'gattpreparequeuefull':
        return UniversalBleErrorCode.operationInProgress;
      // Consolidated: gattAttrNotFound -> serviceNotFound (attribute could be service/characteristic)
      case 'gatt_attr_not_found':
      case 'gattattrnotfound':
        return UniversalBleErrorCode.serviceNotFound;
      // Consolidated: gattAttrNotLong -> invalidAttributeLength
      case 'gatt_attr_not_long':
      case 'gattattrnotlong':
        return UniversalBleErrorCode.invalidAttributeLength;
      // Consolidated: gattUnsupportedGroup -> operationNotSupported
      case 'gatt_unsupported_group':
      case 'gattunsupportedgroup':
        return UniversalBleErrorCode.operationNotSupported;

      // Consolidated: Feature errors -> notSupported
      case 'feature_not_configured':
      case 'featurenotconfigured':
      case 'feature_not_supported':
      case 'featurenotsupported':
      case 'feature_supported':
      case 'featuresupported':
        return UniversalBleErrorCode.notSupported;

      // Consolidated: Profile errors -> failed or notSupported
      case 'error_profile_service_not_bound':
      case 'errorprofileservicenotbound':
        return UniversalBleErrorCode.failed;
      case 'error_missing_bluetooth_connect_permission':
      case 'errormissingbluetoothconnectpermission':
        return UniversalBleErrorCode.bluetoothNotAllowed;
      case 'error_device_not_bonded':
      case 'errordevicenotbonded':
        return UniversalBleErrorCode.notPaired;
      case 'error_gatt_write_not_allowed':
      case 'errorgattwritenotallowed':
        return UniversalBleErrorCode.writeNotPermitted;
      case 'error_gatt_write_request_busy':
      case 'errorgattwriterequestbusy':
        return UniversalBleErrorCode.writeRequestBusy;
      case 'error_unknown':
      case 'errorunknown':
        return UniversalBleErrorCode.unknownError;

      // Web-specific
      case 'webbluetoothgloballydisabled':
      case 'web_bluetooth_globally_disabled':
        return UniversalBleErrorCode.webBluetoothGloballyDisabled;

      default:
        return null;
    }
  }

  /// Maps error message string to UniversalBleErrorCode
  static UniversalBleErrorCode? _mapErrorMessage(String message) {
    final lowerMessage = message.toLowerCase();

    // Characteristic property errors
    if (lowerMessage.contains('does not support read')) {
      return UniversalBleErrorCode.characteristicDoesNotSupportRead;
    }
    if (lowerMessage.contains('does not support write') &&
        lowerMessage.contains('withoutresponse')) {
      return UniversalBleErrorCode
          .characteristicDoesNotSupportWriteWithoutResponse;
    }
    if (lowerMessage.contains('does not support write')) {
      return UniversalBleErrorCode.characteristicDoesNotSupportWrite;
    }
    if (lowerMessage.contains('does not support notify')) {
      return UniversalBleErrorCode.characteristicDoesNotSupportNotify;
    }
    if (lowerMessage.contains('does not support indicate')) {
      return UniversalBleErrorCode.characteristicDoesNotSupportIndicate;
    }

    // Device/Service/Characteristic not found
    if (lowerMessage.contains('unknown deviceid') ||
        lowerMessage.contains('device not found') ||
        lowerMessage.contains('not found')) {
      return UniversalBleErrorCode.deviceNotFound;
    }
    if (lowerMessage.contains('unknown characteristic') ||
        lowerMessage.contains('characteristic not found')) {
      return UniversalBleErrorCode.characteristicNotFound;
    }
    if (lowerMessage.contains('service not found')) {
      return UniversalBleErrorCode.serviceNotFound;
    }
    if (lowerMessage.contains('invalid service uuid')) {
      return UniversalBleErrorCode.invalidServiceUuid;
    }

    // Connection errors
    if (lowerMessage.contains('device disconnected')) {
      return UniversalBleErrorCode.deviceDisconnected;
    }
    if (lowerMessage.contains('connection timeout')) {
      return UniversalBleErrorCode.connectionTimeout;
    }
    if (lowerMessage.contains('connection failed')) {
      return UniversalBleErrorCode.connectionFailed;
    }
    if (lowerMessage.contains('connection already in progress')) {
      return UniversalBleErrorCode.connectionInProgress;
    }

    // Bluetooth availability
    if (lowerMessage.contains('bluetooth not enabled') ||
        lowerMessage.contains('bluetooth is not available')) {
      return UniversalBleErrorCode.bluetoothNotEnabled;
    }

    // Pairing errors
    if (lowerMessage.contains('not paired') &&
        !lowerMessage.contains('already')) {
      return UniversalBleErrorCode.notPaired;
    }
    if (lowerMessage.contains('not pairable')) {
      return UniversalBleErrorCode.notPairable;
    }
    if (lowerMessage.contains('already paired')) {
      return UniversalBleErrorCode.alreadyPaired;
    }
    if (lowerMessage.contains('pairing failed')) {
      return UniversalBleErrorCode.pairingFailed;
    }
    if (lowerMessage.contains('pairing cancelled')) {
      return UniversalBleErrorCode.pairingCancelled;
    }

    // Read/Write errors
    if (lowerMessage.contains('read failed') ||
        lowerMessage.contains('failed to read')) {
      return UniversalBleErrorCode.readFailed;
    }
    if (lowerMessage.contains('write failed') ||
        lowerMessage.contains('failed to write')) {
      return UniversalBleErrorCode.writeFailed;
    }
    if (lowerMessage.contains('no value')) {
      return UniversalBleErrorCode.readFailed;
    }

    return null;
  }

  /// Maps numeric error codes (GATT status, HCI codes, etc.)
  static UniversalBleErrorCode _mapNumericErrorCode(int code) {
    // GATT status codes
    switch (code) {
      case 0x00: // GATT_SUCCESS
        return UniversalBleErrorCode
            .unknownError; // Success, but we need an error
      case 0x01:
        return UniversalBleErrorCode.invalidHandle;
      case 0x02:
        return UniversalBleErrorCode.readNotPermitted;
      case 0x03:
        return UniversalBleErrorCode.writeNotPermitted;
      case 0x04:
        return UniversalBleErrorCode.invalidPdu;
      case 0x05:
        return UniversalBleErrorCode.insufficientAuthentication;
      // Consolidated: gattRequestNotSupported -> operationNotSupported
      case 0x06:
        return UniversalBleErrorCode.operationNotSupported;
      case 0x07:
        return UniversalBleErrorCode.invalidOffset;
      case 0x08:
        return UniversalBleErrorCode.insufficientAuthorization;
      // Consolidated: gattPrepareQueueFull -> operationInProgress
      case 0x09:
        return UniversalBleErrorCode.operationInProgress;
      // Consolidated: gattAttrNotFound -> serviceNotFound
      case 0x0A:
        return UniversalBleErrorCode.serviceNotFound;
      // Consolidated: gattAttrNotLong -> invalidAttributeLength
      case 0x0B:
        return UniversalBleErrorCode.invalidAttributeLength;
      case 0x0C:
        return UniversalBleErrorCode.insufficientKeySize;
      case 0x0D:
        return UniversalBleErrorCode.invalidAttributeLength;
      // Consolidated: gattUnlikely -> failed
      case 0x0E:
        return UniversalBleErrorCode.failed;
      case 0x0F:
        return UniversalBleErrorCode.insufficientEncryption;
      // Consolidated: gattUnsupportedGroup -> operationNotSupported
      case 0x10:
        return UniversalBleErrorCode.operationNotSupported;
      // Consolidated: gattInsufficientResources -> failed
      case 0x11:
        return UniversalBleErrorCode.failed;
      // Consolidated: gattConnectionCongested -> connectionFailed
      case 0x85:
        return UniversalBleErrorCode.connectionFailed;
      // Consolidated: gattFailure -> failed
      case 0x101:
        return UniversalBleErrorCode.failed;
    }
    // HCI error codes - consolidated to higher-level errors
    switch (code) {
      // Connection errors
      case 0x08: // Connection Timeout
      case 0x10: // Connection Accept Timeout Exceeded
        return UniversalBleErrorCode.connectionTimeout;
      case 0x09: // Connection Limit Exceeded
      case 0x0A: // Synchronous Connection Limit To A Device Exceeded
        return UniversalBleErrorCode.connectionLimitExceeded;
      case 0x0B: // Connection Already Exists
        return UniversalBleErrorCode.connectionAlreadyExists;
      case 0x0D: // Connection Rejected due to Limited Resources
      case 0x0F: // Connection Rejected due to Unacceptable BD_ADDR
      case 0x39: // Connection Rejected due to No Suitable Channel Found
        return UniversalBleErrorCode.connectionRejected;
      case 0x0E: // Connection Rejected Due To Security Reasons
        return UniversalBleErrorCode.connectionRejected;
      case 0x13: // Remote User Terminated Connection
      case 0x14: // Remote Device Terminated Connection due to Low Resources
      case 0x15: // Remote Device Terminated Connection due to Power Off
      case 0x16: // Connection Terminated By Local Host
      case 0x3D: // Connection Terminated due to MIC Failure
        return UniversalBleErrorCode.connectionTerminated;
      case 0x3E: // Connection Failed to be Established
      case 0x3F: // MAC Connection Failed
        return UniversalBleErrorCode.connectionFailed;
      // Pairing/Authentication errors
      case 0x05: // Authentication Failure
        return UniversalBleErrorCode.authenticationFailure;
      case 0x18: // Pairing Not Allowed
        return UniversalBleErrorCode.pairingNotAllowed;
      case 0x03: // Hardware Failure
      case 0x29: // Pairing With Unit Key Not Supported
      case 0x37: // Secure Simple Pairing Not Supported By Host
      case 0x38: // Host Busy - Pairing
        return UniversalBleErrorCode.pairingFailed;
      case 0x2F: // Insufficient Security
        return UniversalBleErrorCode.insufficientEncryption;
      // Operation errors
      case 0x0C: // Command Disallowed
      case 0x11: // Unsupported Feature or Parameter Value
      case 0x12: // Invalid HCI Command Parameters
      case 0x1A: // Unsupported Remote Feature
      case 0x1E: // Invalid LMP Parameters
      case 0x20: // Unsupported LMP Parameter Value
        return UniversalBleErrorCode.operationNotSupported;
      case 0x22: // LMP Response Timeout
        return UniversalBleErrorCode.operationTimeout;
      // General errors
      case 0x01: // Unknown HCI Command
      case 0x02: // Unknown Connection Identifier
        return UniversalBleErrorCode.unknownError;
      case 0x04: // Page Timeout
        return UniversalBleErrorCode.connectionTimeout;
      case 0x06: // PIN or Key Missing
        return UniversalBleErrorCode.authenticationFailure;
      case 0x07: // Memory Capacity Exceeded
        return UniversalBleErrorCode.failed;
      case 0x17: // Repeated Attempts
        return UniversalBleErrorCode.failed;
      case 0x25: // Encryption Mode Not Acceptable
        return UniversalBleErrorCode.insufficientEncryption;
      case 0x26: // Link Key cannot be Changed
      case 0x27: // Requested QoS Not Supported
      case 0x2C: // QoS Unacceptable Parameter
      case 0x2D: // QoS Rejected
      case 0x2E: // Channel Classification Not Supported
      case 0x30: // Parameter Out Of Mandatory Range
      case 0x32: // Role Switch Pending
      case 0x35: // Role Switch Failed
      case 0x36: // Extended Inquiry Response Too Large
      case 0x3A: // Controller Busy
      case 0x3B: // Unacceptable Connection Parameters
      case 0x3C: // Advertising Timeout
        return UniversalBleErrorCode.failed;
    }
    // Default to unknown error for unmapped codes
    return UniversalBleErrorCode.unknownError;
  }
}
