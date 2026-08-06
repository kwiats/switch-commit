#!/usr/bin/env bash
# Docker Linux acceptance for the switch-commit CLI:
#   1. Build a release Linux switch-commit binary (natively on Linux hosts,
#      or via a nested `swift:6.2` Linux container on macOS/other hosts).
#   2. Build an Ubuntu 24.04 image that installs that binary.
#   3. Run the container, which drives Scripts/docker/smoke-commands.sh and
#      must print "Docker CLI smoke OK" on success.
#
# Exits non-zero on any failure (build, image build, or smoke assertions).

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
docker_dir="${repo_root}/Scripts/docker"
image_tag="switch-commit-cli-smoke:local"
swift_image_primary="swift:6.2"
swift_image_fallback="swift:6.2-noble"

work_dir="$(mktemp -d /tmp/switch-commit-cli-linux-smoke.XXXXXX)"
cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

echo "==> Staging directory: ${work_dir}"

build_linux_binary_natively() {
  echo "==> Linux host detected: building switch-commit natively"
  (
    cd "${repo_root}"
    swift build -c release --product switch-commit --static-swift-stdlib --scratch-path "${work_dir}/.build-linux-smoke"
  )
  local bin_path="${work_dir}/.build-linux-smoke/release/switch-commit"
  [[ -x "${bin_path}" ]] || { echo "error: native Linux build did not produce ${bin_path}" >&2; exit 1; }
  cp "${bin_path}" "${work_dir}/switch-commit"
}

build_linux_binary_via_docker() {
  local swift_image="$1"
  echo "==> Non-Linux host detected: building switch-commit via ${swift_image} container"
  docker run --rm \
    -v "${repo_root}:/src:ro" \
    -w /src \
    -v "${work_dir}:/out" \
    "${swift_image}" \
    bash -lc 'swift build -c release --product switch-commit --static-swift-stdlib --scratch-path /tmp/build-linux && cp "$(swift build -c release --static-swift-stdlib --scratch-path /tmp/build-linux --show-bin-path)/switch-commit" /out/switch-commit'
}

build_linux_binary_via_docker_with_fallback() {
  if docker pull "${swift_image_primary}" >/dev/null 2>&1; then
    build_linux_binary_via_docker "${swift_image_primary}"
    return
  fi

  echo "==> ${swift_image_primary} unavailable, trying ${swift_image_fallback}"
  if docker pull "${swift_image_fallback}" >/dev/null 2>&1; then
    build_linux_binary_via_docker "${swift_image_fallback}"
    return
  fi

  echo "error: neither ${swift_image_primary} nor ${swift_image_fallback} could be pulled" >&2
  exit 1
}

host_os="$(uname -s)"
case "${host_os}" in
  Linux)
    build_linux_binary_natively
    ;;
  *)
    command -v docker >/dev/null 2>&1 || { echo "error: docker is required to build the Linux binary on ${host_os}" >&2; exit 1; }
    build_linux_binary_via_docker_with_fallback
    ;;
esac

[[ -x "${work_dir}/switch-commit" ]] || { echo "error: missing built binary at ${work_dir}/switch-commit" >&2; exit 1; }
echo "==> Built Linux switch-commit binary: $(du -h "${work_dir}/switch-commit" | cut -f1)"

echo "==> Staging Docker build context"
cp "${docker_dir}/Dockerfile.cli-smoke" "${work_dir}/Dockerfile.cli-smoke"
cp "${docker_dir}/smoke-commands.sh" "${work_dir}/smoke-commands.sh"

echo "==> Building smoke test image (${image_tag})"
docker build \
  -f "${work_dir}/Dockerfile.cli-smoke" \
  -t "${image_tag}" \
  "${work_dir}"

echo "==> Running Docker Linux CLI smoke"
output_file="${work_dir}/smoke-output.log"
if ! docker run --rm "${image_tag}" | tee "${output_file}"; then
  echo "error: switch-commit-cli-smoke container exited non-zero" >&2
  exit 1
fi

grep -q "Docker CLI smoke OK" "${output_file}" || {
  echo "error: smoke output did not contain the expected success marker" >&2
  exit 1
}

echo "==> Docker Linux CLI smoke passed"
