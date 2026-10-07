module vcraft_wheel

// The metadata files a wheel has to carry.
//
// A wheel is installable because of these: `WHEEL` says how it was built, `METADATA`
// says what the package is, and `RECORD` is the hash of everything, which is what
// makes a wheel verifiable and uninstallable.

// MetaData is what goes into a `METADATA` file.
pub struct MetaData {
pub mut:
	name        string
	version     string
	summary     string
	description string
	// description_content_type is the MIME type of `description`, e.g.
	// `text/markdown`. Without it PyPI renders a Markdown README as plain text.
	description_content_type string
	license     string
	// keywords, e.g. `parser`, written comma-separated.
	keywords []string
	// project_urls, each `Label, https://...`.
	project_urls []string
	requires_python string
	// classifiers, e.g. `Programming Language :: Other`. PyPI rejects unknown ones.
	classifiers []string
	// requires_dist, e.g. `requests>=2`.
	requires_dist []string
}

// render_metadata writes a PEP 566 `METADATA` file.
//
// Fields are separated by a blank line from the body, and the body is the long
// description. A file with the fields in the wrong order, or with the body before
// them, is rejected by the installer's parser with a message that does not name the
// field.
pub fn render_metadata(m MetaData) string {
	mut out := 'Metadata-Version: 2.1\n'
	out += 'Name: ${m.name}\n'
	out += 'Version: ${m.version}\n'
	if m.summary.len > 0 {
		out += 'Summary: ${m.summary}\n'
	}
	if m.license.len > 0 {
		out += 'License: ${m.license}\n'
	}
	if m.keywords.len > 0 {
		out += 'Keywords: ${m.keywords.join(',')}\n'
	}
	for u in m.project_urls {
		out += 'Project-URL: ${u}\n'
	}
	if m.requires_python.len > 0 {
		out += 'Requires-Python: ${m.requires_python}\n'
	}
	for c in m.classifiers {
		out += 'Classifier: ${c}\n'
	}
	for r in m.requires_dist {
		out += 'Requires-Dist: ${r}\n'
	}
	if m.description.len > 0 && m.description_content_type.len > 0 {
		out += 'Description-Content-Type: ${m.description_content_type}\n'
	}
	if m.description.len > 0 {
		out += '\n${m.description}\n'
	}
	return out
}

// render_wheel writes the `WHEEL` file.
//
// `Root-Is-Purelib: false` is what tells the installer this belongs in the platform's
// library directory rather than with the pure-Python packages. A wheel holding a
// compiled extension that claims to be pure is installed somewhere import cannot find
// it, and the failure appears as an ImportError much later.
pub fn render_wheel(tags string, generator string) string {
	mut out := 'Wheel-Version: 1.0\n'
	out += 'Generator: ${generator}\n'
	out += 'Root-Is-Purelib: false\n'
	for tag in tags.split(',') {
		out += 'Tag: ${tag}\n'
	}
	return out
}

// RECORD row format: path,sha256=<urlsafe base64 without padding>,size
//
// The hash is base64 rather than hex because that is what PEP 376 specifies, and the
// padding is stripped because a `=` in the middle of a CSV field breaks naive readers.
pub fn record_row(path string, data []u8, hash bool) string {
	// RECORD itself gets no hash: a file cannot contain its own digest.
	if !hash {
		return '${path},,\n'
	}
	return '${path},sha256=${sha256_record(data)},${data.len}\n'
}
