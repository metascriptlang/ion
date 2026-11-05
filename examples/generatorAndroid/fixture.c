#include "fixture.h"
#include <android/log.h>
#include <jni.h>
#include <stdio.h>
#include <string.h>

extern void MsMain(void);

static int32_t fixtureValue;
static int started;
static jobject label;
static jobject activity;
static char assetResult[160];

static void report(const char *event) {
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "%s value=%d", event, fixtureValue);
}

void ionFixtureAsset(const char *result) {
	snprintf(assetResult, sizeof assetResult, "%s", result);
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
	if (activity) (*env)->DeleteGlobalRef(env, activity);
	activity = (*env)->NewGlobalRef(env, context);
	report("start");
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "asset %s", assetResult);
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
	if (activity) (*env)->DeleteGlobalRef(env, activity);
	activity = NULL;
	report("destroy");
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_newIntent(JNIEnv *env, jclass cls, jobject intent) {
	(void)cls;
	jstring data = (*env)->CallObjectMethod(env, intent,
		(*env)->GetMethodID(env, (*env)->GetObjectClass(env, intent), "getDataString", "()Ljava/lang/String;"));
	const char *text = data ? (*env)->GetStringUTFChars(env, data, NULL) : NULL;
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "newIntent data=%s value=%d", text ? text : "", fixtureValue);
	int askPermission = text && strcmp(text, "ionfixture://permission") == 0;
	int askResult = text && strcmp(text, "ionfixture://result") == 0;
	if (text) (*env)->ReleaseStringUTFChars(env, data, text);
	if (!activity || (!askPermission && !askResult)) return;
	jclass activityClass = (*env)->GetObjectClass(env, activity);
	if (askPermission) {
		jobjectArray names = (*env)->NewObjectArray(env, 1, (*env)->FindClass(env, "java/lang/String"),
			(*env)->NewStringUTF(env, "android.permission.CAMERA"));
		(*env)->CallVoidMethod(env, activity,
			(*env)->GetMethodID(env, activityClass, "requestPermissions", "([Ljava/lang/String;I)V"), names, 41);
	}
	if (askResult) {
		jclass intentClass = (*env)->FindClass(env, "android/content/Intent");
		jobject echo = (*env)->NewObject(env, intentClass,
			(*env)->GetMethodID(env, intentClass, "<init>", "(Landroid/content/Context;Ljava/lang/Class;)V"),
			activity, (*env)->FindClass(env, "dev/ion/fixture/Echo"));
		(*env)->CallVoidMethod(env, activity,
			(*env)->GetMethodID(env, activityClass, "startActivityForResult", "(Landroid/content/Intent;I)V"), echo, 42);
	}
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_permissionsResult(JNIEnv *env, jclass cls, jint requestCode,
	jobjectArray permissions, jintArray grantResults) {
	(void)cls;
	jstring name = (*env)->GetArrayLength(env, permissions) > 0 ? (*env)->GetObjectArrayElement(env, permissions, 0) : NULL;
	const char *text = name ? (*env)->GetStringUTFChars(env, name, NULL) : NULL;
	jint grant = -2;
	if ((*env)->GetArrayLength(env, grantResults) > 0) (*env)->GetIntArrayRegion(env, grantResults, 0, 1, &grant);
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "permissionsResult code=%d %s=%d value=%d",
		requestCode, text ? text : "", grant, fixtureValue);
	if (text) (*env)->ReleaseStringUTFChars(env, name, text);
}

JNIEXPORT void JNICALL Java_dev_metascript_app_NativeApp_activityResult(JNIEnv *env, jclass cls, jint requestCode,
	jint resultCode, jobject data) {
	(void)cls;
	jstring uri = data ? (*env)->CallObjectMethod(env, data,
		(*env)->GetMethodID(env, (*env)->GetObjectClass(env, data), "getDataString", "()Ljava/lang/String;")) : NULL;
	const char *text = uri ? (*env)->GetStringUTFChars(env, uri, NULL) : NULL;
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "activityResult code=%d result=%d data=%s value=%d",
		requestCode, resultCode, text ? text : "", fixtureValue);
	if (text) (*env)->ReleaseStringUTFChars(env, uri, text);
}

JNIEXPORT void JNICALL Java_dev_ion_fixture_Tap_tapped(JNIEnv *env, jclass cls, jint tag) {
	(void)env;
	(void)cls;
	__android_log_print(ANDROID_LOG_INFO, "IonFixture", "tap tag=%d value=%d", tag, fixtureValue);
}
