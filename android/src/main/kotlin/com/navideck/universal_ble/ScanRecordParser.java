package com.navideck.universal_ble;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothDevice;
import android.util.Log;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;

@SuppressLint("MissingPermission")
public class ScanRecordParser {

    public static void handleLeScanRecord(BluetoothDevice bluetoothDevice, byte[] bArr) {
        int i9;
        if (bArr == null) {
            return;
        }
        byte[] copyOf = Arrays.copyOf(bArr, bArr.length);
        String deviceName = m19206z0(bluetoothDevice.getName());
        byte[] bArr2 = new byte[9];
        int i10 = 0;
        while (i10 < copyOf.length - 2 && copyOf.length > i10 && i10 >= 0 && (i9 = copyOf[i10]) != 0 && i9 >= 0) {
            int i11 = i10 + 1;
            byte b9 = copyOf[i11];
            if (b9 == -1) {
                int i12 = 0;
                for (int i13 = 0; i13 < i9 - 1; i13++) {
                    i11++;
                    if (9 <= i12 || bArr.length <= i11) {
                        break;
                    }
                    bArr2[i12] = bArr[i11];
                    if (bArr2[0] != 58) {
                        break;
                    }
                    i12++;
                }
                i10 = i11 + 1;
            } else if (b9 != 9) {
                i10 = i11 + i9;
            } else {
                byte[] bArr3 = new byte[i9];
                int i14 = 0;
                for (int i15 = 0; i15 < i9 - 1 && bArr.length > (i11 = i11 + 1); i15++) {
                    bArr3[i14] = bArr[i11];
                    i14++;
                }
                i10 = i11 + 1;
                if (deviceName == null) {
                    deviceName = getDeviceName(bArr3);
                }
            }
        }
        if (bArr2[0] != 58) {
            return;
        }
        String state = getState(bArr2[2]);
        String publicAddress = getPublicAddress(Arrays.copyOfRange(bArr2, 3, 9));
        Log.e("ScanRecord", "Name: " + deviceName + " State: " + state + " Address: " + publicAddress);
    }

    public static String getState(byte b9) {
        return b9 == 0 ? "normal" : b9 == 1 ? "sleep" : b9 == 2 ? "wakeup" : b9 == 3 ? "pairing" : b9 == 4 ? "sleep_pow_off" : b9 == 5 ? "sleep_pow_on" : b9 == 6 ? "sleep_pow_off_fast" : b9 == 7 ? "sleep_pow_on_fast" : b9 == 8 ? "sleep_pow_on_autotrans" : b9 == 9 ? "sleep_pow_off_fast_autotrans" : b9 == 10 ? "sleep_pow_on_fast_autotrans" : "";
    }

    public static String getPublicAddress(byte[] bArr) {
        int length;
        int i8 = 0;
        String str = "";
        for (byte b9 : bArr) {
            str = str + String.valueOf((int) b9);
        }
        if (bArr[bArr.length - 1] != 0) {
            i8 = String.valueOf((int) bArr[0]).length();
            length = str.length();
        } else {
            length = str.length() - 1;
        }
        return str.substring(i8, length);
    }


    public static String m19206z0(String str) {
        return (str == null || str.length() <= 2 || str.getBytes()[str.getBytes().length - 2] != 32) ? str : str.substring(0, str.length() - 2);
    }

    public static String getDeviceName(byte[] bArr) {
        return new String(bArr, StandardCharsets.UTF_8);
    }

}
