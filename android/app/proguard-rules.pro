# ============================================================
# R8 / ML Kit keep rules
# ============================================================

# Google ML Kit
-keep class com.google.mlkit.** { *; }

# ML Kit internal vision classes
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }

# Android On-Device Machine Learning
-keep class com.google.android.odml.** { *; }

# Keep Firebase ComponentRegistrar constructors.
# Required for components that are instantiated through reflection.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    void <init>();
}

# Keep annotations and generic signatures used by ML Kit
-keepattributes *Annotation*
-keepattributes Signature

# Keep source line information to make release stack traces
# easier to diagnose if a runtime exception remains.
-keepattributes SourceFile,LineNumberTable
