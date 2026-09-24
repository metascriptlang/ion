package dev.ion.fixture;

import android.view.View;

public final class Tap implements View.OnClickListener {
	private final int tag;

	public Tap(int tag) {
		this.tag = tag;
	}

	@Override
	public void onClick(View view) {
		tapped(tag);
	}

	static native void tapped(int tag);
}
