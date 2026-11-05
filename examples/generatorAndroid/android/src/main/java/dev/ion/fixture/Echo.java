package dev.ion.fixture;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

public final class Echo extends Activity {
	@Override
	protected void onCreate(Bundle state) {
		super.onCreate(state);
		setResult(RESULT_OK, new Intent().setData(Uri.parse("ionfixture://echo")));
		finish();
	}
}
