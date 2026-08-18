# ProGuard / R8 rules applied to consumers of `io.parity:truapi-provider-android`.
#
# JNA reflects into our generated UniFFI types at runtime, so the bindings
# package must survive shrinking.

-keep class uniffi.truapi_provider.** { *; }

# JNA itself.
-keep class com.sun.jna.** { *; }
-keepclassmembers class * extends com.sun.jna.** { *; }
