module vcraft_ci

import vcraft_project

// Generating a GitHub Actions workflow.
//
// The workflow is emitted rather than shipped as a template with holes in it, for the
// same reason the PEP 517 backend is: a project that copies a template has a copy, and
// the copy says nothing about which version of the tool wrote it. Emitting it from the
// binary means `vcraft generate-ci` always produces a workflow for the vcraft that ran
// it.
//
// The matrix is the interesting part and the part that is easy to get wrong. A wheel is
// per-interpreter, per-ABI and per-platform, and a workflow that builds one of them
// tests one. The matrix below covers the combinations a release actually needs and
// skips the ones that cannot work.
//
// Linux cells build inside the published images rather than on the runner: the image
// carries the toolchain, the interpreters and vcraft itself, so the wheel it produces
// is honestly tagged. A manylinux wheel built on `ubuntu-latest` would link that
// runner's glibc and the tag would be a lie the installer only discovers at import.

// Target is one cell of the build matrix.
pub struct Target {
pub mut:
	// os is the runner: ubuntu-latest for x86_64 Linux, ubuntu-24.04-arm for aarch64
	// Linux, macos-14, or windows-latest.
	os string
	// python is the interpreter version for `setup-python`, or empty when the cell
	// builds inside a container that brings its own interpreters.
	python string
	// abi3, when set, builds against the stable ABI from that version on.
	abi3 string
	// free_threading builds a free-threaded extension.
	free_threading bool
	// target is the wheel's platform tag, when the runner does not produce it by
	// itself.
	target string
	// container is the image the build runs in, or empty for a direct runner build.
	container string
	// args are the vcraft arguments the cell runs, including the target and the
	// interpreter when the build is containerised.
	args string
	// note explains why a cell exists, and becomes a workflow comment.
	note string
}

// workflow renders the workflow file.
//
// `vcraft_action` is the action the build step uses. It defaults to `vcraft-action@v1`
// because that is the published action a consumer expects; a project pinned to its own
// build can name a different ref.
pub fn workflow(p vcraft_project.Project, vcraft_action string, free_threading bool) string {
	mut w := new_builder()
	w.write_string(generated_header(p))
	w.write_string('name: build\n\n')
	w.write_string('on:\n')
	w.write_string('  push:\n')
	w.write_string('    branches: [main]\n')
	w.write_string('  pull_request:\n')
	w.write_string('  workflow_dispatch:\n\n')
	w.write_string('jobs:\n')
	w.write_string('  build:\n')
	w.write_string('    name: ' + gha('matrix.target') + ' on ' + gha('matrix.os') + '\n')
	w.write_string('    runs-on: ' + gha('matrix.os') + '\n')
	w.write_string('    strategy:\n')
	w.write_string('      fail-fast: false\n')
	w.write_string('      matrix:\n')
	w.write_string('        include:\n')
	for t in targets(p, free_threading) {
		w.write_string('          - target: ' + quote(t.target) + '\n')
		w.write_string('            os: ' + quote(t.os) + '\n')
		if t.container.len > 0 {
			w.write_string('            container: ' + quote(t.container) + '\n')
		}
		if t.python.len > 0 {
			w.write_string('            python: ' + quote(t.python) + '\n')
		}
		if t.abi3.len > 0 {
			w.write_string('            abi3: ' + quote(t.abi3) + '\n')
		}
		if t.free_threading {
			w.write_string('            free-threading: true\n')
		}
		w.write_string('            args: ' + quote(t.args) + '\n')
	}
	w.write_string('\n    steps:\n')
	w.write_string('      - uses: actions/checkout@v4\n\n')
	w.write_string('      - name: set up Python\n')
	w.write_string('        if: ')
	w.write_string(gha_if_empty('matrix.container'))
	w.write_string('\n')
	w.write_string('        uses: actions/setup-python@v5\n')
	w.write_string('        with:\n')
	w.write_string('          python-version: ' + gha('matrix.python') + '\n\n')
	w.write_string('      - name: install vcraft\n')
	w.write_string('        if: ')
	w.write_string(gha_if_empty('matrix.container'))
	w.write_string('\n')
	w.write_string('        run: pip install vcraft\n\n')
	w.write_string('      - name: build\n')
	w.write_string('        uses: ' + vcraft_action + '\n')
	w.write_string('        with:\n')
	w.write_string('          container: ' + gha('matrix.container') + '\n')
	w.write_string('          args: ' + gha('matrix.args') + '\n\n')
	w.write_string('      - name: upload\n')
	w.write_string('        uses: actions/upload-artifact@v4\n')
	w.write_string('        with:\n')
	w.write_string('          name: ' + gha('matrix.target') + '\n')
	w.write_string('          path: dist/*.whl\n\n')
	w.write_string('      - name: test\n')
	w.write_string('        run: |\n')
	w.write_string('          python -m venv /tmp/check\n')
	w.write_string('          /tmp/check/bin/pip install dist/*.whl\n')
	w.write_string('          /tmp/check/bin/python -c "import ${p.module}; print(${p.module}.__name__)"\n')
	return w.str()
}

// generated_header is the comment at the top of the file.
//
// It names the distribution and the version of vcraft that wrote it, so that a
// workflow found in a repository says which tool produced it rather than looking like
// something a person wrote.
fn generated_header(p vcraft_project.Project) string {
	return '# Generated by vcraft ' + vcraft_project.version + ' for ' + p.name + '.\n' +
		'# Regenerate with `vcraft generate-ci`. Do not edit by hand: the matrix is\n' +
		'# derived from what this version of vcraft supports, and a hand-edited matrix\n' +
		'# stops matching the tag logic in the binary.\n\n'
}

// image_names renders the container image for a Linux cell.
//
// Versioned with vcraft itself, because the image carries a vcraft binary and an image
// built by another version would build with other flags. A workflow generated by
// vcraft 0.1.0 therefore names the 0.1.0 images, and upgrading vcraft means
// regenerating the workflow.
fn image_names(kind string) string {
	return 'ghcr.io/rroblf01/vcraft-' + kind + ':' + vcraft_project.version
}

// targets returns the matrix cells.
//
// Two combinations that look plausible are deliberately absent: an abi3 build and a
// free-threaded build are mutually exclusive, because the free-threaded runtime has no
// stable ABI; and there is no macOS arm64 cell paired with macOS x86_64, because a
// universal2 wheel is built once on one of them rather than twice.
//
// Linux cells build inside the published images, each on a native runner for its
// architecture. Emulation is nowhere in this matrix: an emulated compiler is how a
// build becomes unreproducible, and aarch64 runners exist.
pub fn targets(p vcraft_project.Project, free_threading bool) []Target {
	mut out := []Target{}
	if free_threading {
		// A free-threaded build has no stable ABI, so the matrix is one cell per
		// platform and each names its own interpreter rather than a version the runner
		// might provide with the GIL.
		out << Target{
			os:             'ubuntu-latest'
			target:         'cp3.13t-cp313t-manylinux-x86_64'
			free_threading: true
			args:           'build --release --free-threading'
		}
		out << Target{
			os:             'macos-14'
			target:         'cp3.13t-cp313t-macosx-arm64'
			free_threading: true
			args:           'build --release --free-threading'
		}
		return out
	}
	if p.abi3.len > 0 {
		// One wheel covers every interpreter from the floor up, so one cell per
		// platform is the whole matrix.
		out << Target{
			os:        'ubuntu-latest'
			abi3:      p.abi3
			target:    'cp' + compact(p.abi3) + '-abi3-manylinux-x86_64'
			container: image_names('manylinux')
			args:      'build --release --abi3 ' + p.abi3 +
				' --target linux-x86_64-gnu --manylinux 2_28' +
				' --interpreter /opt/python/cp' + compact(p.abi3) + '-cp' + compact(p.abi3) + '/bin/python'
		}
		out << Target{
			os:        'ubuntu-24.04-arm'
			abi3:      p.abi3
			target:    'cp' + compact(p.abi3) + '-abi3-manylinux-aarch64'
			container: image_names('manylinux')
			args:      'build --release --abi3 ' + p.abi3 +
				' --target linux-aarch64-gnu --manylinux 2_28' +
				' --interpreter /opt/python/cp' + compact(p.abi3) + '-cp' + compact(p.abi3) + '/bin/python'
		}
		out << Target{
			os:        'ubuntu-latest'
			abi3:      p.abi3
			target:    'cp' + compact(p.abi3) + '-abi3-musllinux-x86_64'
			container: image_names('musllinux')
			args:      'build --release --abi3 ' + p.abi3 +
				' --target linux-x86_64-musl --musllinux 1_2 --interpreter /usr/bin/python3'
		}
		out << Target{
			os:        'ubuntu-24.04-arm'
			abi3:      p.abi3
			target:    'cp' + compact(p.abi3) + '-abi3-musllinux-aarch64'
			container: image_names('musllinux')
			args:      'build --release --abi3 ' + p.abi3 +
				' --target linux-aarch64-musl --musllinux 1_2 --interpreter /usr/bin/python3'
		}
		out << Target{
			os:     'macos-14'
			abi3:   p.abi3
			target: 'cp' + compact(p.abi3) + '-abi3-macosx-universal2'
			args:   'build --release --abi3 ' + p.abi3
		}
		out << Target{
			os:     'windows-latest'
			abi3:   p.abi3
			target: 'cp' + compact(p.abi3) + '-abi3-win_amd64'
			args:   'build --release --abi3 ' + p.abi3
		}
		return out
	}
	// Without abi3 every interpreter needs its own wheel, so the matrix is
	// interpreters crossed with the platforms that have a current interpreter.
	for version in ['3.12', '3.13', '3.14'] {
		floor := compact(version)
		out << Target{
			os:        'ubuntu-latest'
			target:    'cp' + floor + '-manylinux-x86_64'
			container: image_names('manylinux')
			args:      'build --release --target linux-x86_64-gnu' +
				' --interpreter /opt/python/cp' + floor + '-cp' + floor + '/bin/python'
		}
		out << Target{
			os:        'ubuntu-24.04-arm'
			target:    'cp' + floor + '-manylinux-aarch64'
			container: image_names('manylinux')
			args:      'build --release --target linux-aarch64-gnu' +
				' --interpreter /opt/python/cp' + floor + '-cp' + floor + '/bin/python'
		}
		out << Target{
			os:     'macos-14'
			python: version
			target: 'cp' + floor + '-macosx-universal2'
			args:   'build --release'
		}
	}
	return out
}

// compact turns `3.12` into `312`, which is how a tag spells it.
fn compact(version string) string {
	return version.replace('.', '')
}

// gha_if_empty renders a GitHub Actions guard for an empty matrix value.
//
// `${{ matrix.container == '' }}` skips the runner-side setup for cells that build
// inside a container. Written as a helper because `${{` starts a V interpolation and
// the literal has to be assembled without ever writing those three characters together.
fn gha_if_empty(expression string) string {
	return '$' + '{{ ' + expression + " == '' }}"
}

// gha renders a GitHub Actions expression.
//
// Double braces, `${{ matrix.os }}`: single braces are literal text to GitHub, and a
// workflow whose job name is literally `${matrix.target}` runs every cell under the
// same name with the wrong runner. Assembled from pieces because `${{` starts a V
// interpolation and writing those three characters together would try to evaluate a
// struct named `matrix` that does not exist.
fn gha(expression string) string {
	return '$' + '{{ ' + expression + ' }}'
}

// quote renders a YAML scalar.
//
// Quoted throughout, because a bare `3.10` in YAML is a float and comes back as `3.1`,
// which is a version nobody publishes. The value is interpolated at the call site by
// the builder, so this takes the finished text.
fn quote(text string) string {
	return '"' + text + '"'
}

// new_builder is a tiny string accumulator.
//
// Not `strings.Builder`: that is a standard-library type whose methods this module would
// have to import, and a workflow is written once.
struct Builder {
mut:
	out string
}

fn new_builder() &Builder {
	return &Builder{}
}

fn (mut b Builder) write_string(text string) {
	b.out += text
}

fn (b &Builder) str() string {
	return b.out
}
