package com.navideck.universal_ble

import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain

/**
 * Installs a Main dispatcher for tests that exercise code delivering Dart
 * callbacks through `Dispatchers.Main`, which is otherwise unavailable on the
 * JVM. Extend this instead of duplicating the set/reset in each test class.
 */
internal abstract class MainDispatcherTest {
    @BeforeTest
    fun setUpMainDispatcher() {
        Dispatchers.setMain(Dispatchers.Unconfined)
    }

    @AfterTest
    fun tearDownMainDispatcher() {
        Dispatchers.resetMain()
    }
}
