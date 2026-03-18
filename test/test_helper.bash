# Test helper — extracts validation functions from setup.sh for unit testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Define color vars (needed by err/warn functions)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*"; }
die()     { echo -e "${RED}[FATAL]${NC} $*"; exit 1; }

# Source validation functions directly
validate_input() {
  local value="$1" label="$2"
  if [[ -z "$value" ]]; then err "Empty value for ${label}"; return 1; fi
  if [[ "$value" =~ [[:cntrl:]] ]]; then err "${label}: control characters not allowed"; return 1; fi
  if [[ "$value" =~ [\;\|\&\`\$\(\)\{\}\<\>\!\#] ]]; then err "${label}: special characters not allowed"; return 1; fi
  if [[ "$value" == *".."* ]]; then err "${label}: path traversal (..) not allowed"; return 1; fi
  if [[ "$value" =~ [\"\'] ]]; then err "${label}: quotes not allowed"; return 1; fi
  return 0
}

validate_name() {
  local value="$1" label="$2"
  if ! [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then err "${label}: invalid name"; return 1; fi
  if [[ ${#value} -gt 64 ]]; then err "${label}: too long"; return 1; fi
  return 0
}

validate_port() {
  local port="$1"
  if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then err "Invalid port"; return 1; fi
  return 0
}

validate_path() {
  local path="$1" label="$2"
  if [[ "$path" != /* ]]; then err "${label}: must be absolute path"; return 1; fi
  if [[ "$path" == *".."* ]]; then err "${label}: path traversal not allowed"; return 1; fi
  if [[ "$path" =~ [[:cntrl:]] ]]; then err "${label}: control characters not allowed"; return 1; fi
  return 0
}

validate_token() {
  local token="$1" label="${2:-token}"
  if [[ -z "$token" ]]; then return 1; fi
  if [[ "$token" =~ [[:space:]] ]]; then err "${label}: whitespace not allowed"; return 1; fi
  if [[ "$token" =~ [[:cntrl:]] ]]; then err "${label}: control characters not allowed"; return 1; fi
  return 0
}
