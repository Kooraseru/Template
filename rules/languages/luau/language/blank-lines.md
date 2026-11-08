# Blank-line separation

Separate adjacent multi-line module-level statements with a blank line. This keeps complete functions, control-flow blocks, and other multi-line sections visually distinct. Keep tightly related single-line declarations together; do not add blank lines mechanically between every statement.

The [validator](blank-lines/README.md) currently checks module-level statement boundaries. Nested blocks remain a review area until their separation policy is defined without making ordinary control flow noisy.
