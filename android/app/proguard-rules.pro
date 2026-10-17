# ONNX JNI looks up these Java classes, constructors and fields by name.
# Removing or renaming them aborts the process on the first inference call.
# https://onnxruntime.ai/docs/build/android.html
-keep class ai.onnxruntime.** { *; }
