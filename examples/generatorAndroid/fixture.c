#include "fixture.h"
#include <android/log.h>
#include <jni.h>
#include <stdio.h>

extern void MsMain(void);

static int32_t fixtureValue;
static int started;
static jobject label;

static void report(const char *event) {
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "%s value=%d", event, fixtureValue);
}

void ionFixtureRun(int32_t value) {
	fixtureValue = value + ION_FIXTURE_VALUE + 0;
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_start(JNIEnv *env, jclass cls, jobject root) {
	(void)cls;
	if (!started) {
		started = 1;
		MsMain();
	}
	jclass viewGroup = (*env)->GetObjectClass(env, root);
	jobject context = (*env)->CallObjectMethod(env, root,
		(*env)->GetMethodID(env, viewGroup, "getContext", "()Landroid/content/Context;"));
	jclass textView = (*env)->FindClass(env, "android/widget/TextView");
	jobject view = (*env)->NewObject(env, textView,
		(*env)->GetMethodID(env, textView, "<init>", "(Landroid/content/Context;)V"), context);
	char text[64];
	snprintf(text, sizeof text, "Ion Android native value: %d", fixtureValue);
	(*env)->CallVoidMethod(env, view,
		(*env)->GetMethodID(env, textView, "setText", "(Ljava/lang/CharSequence;)V"), (*env)->NewStringUTF(env, text));
	(*env)->CallVoidMethod(env, view, (*env)->GetMethodID(env, textView, "setTextSize", "(F)V"), 24.0f);
	(*env)->CallVoidMethod(env, root,
		(*env)->GetMethodID(env, viewGroup, "addView", "(Landroid/view/View;)V"), view);
	if (label) (*env)->DeleteGlobalRef(env, label);
	label = (*env)->NewGlobalRef(env, view);
	report("start");
	jclass tap = (*env)->FindClass(env, "dev/ion/fixture/Tap");
	if (tap) {
		jobject listener = (*env)->NewObject(env, tap, (*env)->GetMethodID(env, tap, "<init>", "(I)V"), 7);
		(*env)->CallVoidMethod(env, view,
			(*env)->GetMethodID(env, textView, "setOnClickListener", "(Landroid/view/View$OnClickListener;)V"), listener);
		__android_log_print(ANDROID_LOG_INFO, "IonFixture", "listener=attached");
	} else {
		(*env)->ExceptionClear(env);
		__android_log_print(ANDROID_LOG_INFO, "IonFixture", "listener=missing");
	}
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_resize(JNIEnv *env, jclass cls, jint width, jint height) {
	(void)env;
	(void)cls;
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "resize %dx%d value=%d", width, height, fixtureValue);
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_pause(JNIEnv *env, jclass cls) {
	(void)env;
	(void)cls;
	report("pause");
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_resume(JNIEnv *env, jclass cls) {
	(void)env;
	(void)cls;
	report("resume");
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_destroy(JNIEnv *env, jclass cls) {
	(void)cls;
	if (label) (*env)->DeleteGlobalRef(env, label);
	label = NULL;
	report("destroy");
}

JNIEXPORT void JNICALL Java_dev_ion_fixture_Tap_tapped(JNIEnv *env, jclass cls, jint tag) {
	(void)env;
	(void)cls;
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "tap tag=%d value=%d", tag, fixtureValue);
}
