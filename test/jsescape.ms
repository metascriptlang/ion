// Tests for jsEscape — pure string transformation, no platform deps.

import { jsEscape } from "../src/internal/jsEscape";

test "plain ASCII passes through unchanged" {
	assert jsEscape("hello world") === "hello world";
	assert jsEscape("123 abc") === "123 abc";
}

test "double-quote is escaped" {
	assert jsEscape("a\"b") === "a\\\"b";
}

test "backslash is escaped" {
	assert jsEscape("a\\b") === "a\\\\b";
}

test "newline is escaped to \\n" {
	assert jsEscape("a\nb") === "a\\nb";
}

test "carriage return is escaped to \\r" {
	assert jsEscape("a\rb") === "a\\rb";
}

test "empty string stays empty" {
	assert jsEscape("") === "";
}

test "combined escape: backslash before quote (must escape backslash first)" {
	// Input: \" should become \\\"  (4 chars: backslash, backslash, backslash, quote)
	assert jsEscape("\\\"") === "\\\\\\\"";
}

test "multiple newlines" {
	assert jsEscape("a\nb\nc") === "a\\nb\\nc";
}
