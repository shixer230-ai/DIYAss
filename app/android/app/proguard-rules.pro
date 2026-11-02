# ML Kit 组件注册器通过 manifest 的 meta-data 反射按类名实例化（走 no-arg 构造器），
# R8 full mode 会剥离这些无参构造器，导致运行时反射拿到 null（getClass on null 崩溃）。
# 必须保留所有实现 ComponentRegistrar 接口的类的无参构造器。
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google.mlkit.**Registrar { <init>(); }

# ML Kit 及 bundled 中文模型的内部类大量用反射，整体保留避免运行时 NPE
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }

# 文字识别插件反射加载多语言识别器，本 App 只 bundled 中文（text-recognition-chinese），
# 其余语言（日/韩/梵文等）识别器类不在依赖里，R8 裁剪时忽略缺失即可
-dontwarn com.google.mlkit.vision.text.**
