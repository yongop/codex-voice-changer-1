#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
cd "${PROJECT_DIR}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    print -u2 "This directory is not a Git work tree."
    exit 69
fi

tracked_count=0
failed=0
while IFS= read -r -d '' tracked_file; do
    (( tracked_count += 1 ))
    case "${tracked_file}" in
        .env|.env.*|*.pem|*.key|*.p12|*.mobileprovision|*.secrets.*|\
        *.wav|*.wave|*.mp3|*.m4a|*.aac|*.flac|*.mp4|*.mov|\
        *.pth|*.pt|*.bin|*.mlpackage/*|*.mlmodelc/*|\
        .training_cache/*|outputs/*|dist/*|voice_analysis_work/*|\
        voice_training/*|VOICE_RESEARCH.md)
            print -u2 "Blocked public file: ${tracked_file}"
            failed=1
            ;;
    esac

    if [[ -f "${tracked_file}" ]]; then
        file_size="$(stat -f '%z' "${tracked_file}")"
        if (( file_size > 10 * 1024 * 1024 )); then
            print -u2 "Tracked file exceeds 10 MiB: ${tracked_file}"
            failed=1
        fi
    fi
done < <(git ls-files -z)

if (( tracked_count == 0 )); then
    print -u2 "No tracked files found. Stage the public tree first with git add ."
    exit 69
fi

secret_pattern='(AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|gh[pousr]_[0-9A-Za-z]{20,}|sk-[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{20,}|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY)'
if git grep --cached -I -n -E "${secret_pattern}" -- \
    ':!Scripts/audit-public-tree.sh'; then
    print -u2 "Possible secret found in the public tree."
    failed=1
fi

if git grep --cached -I -n -E '(/Users/[^/]+/|/home/[^/]+/)' -- \
    ':!Scripts/audit-public-tree.sh'; then
    print -u2 "Absolute user path found in the public tree."
    failed=1
fi

if (( failed != 0 )); then
    exit 1
fi

print "Public tree audit passed (${tracked_count} tracked files)."
