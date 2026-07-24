# Shared mutable state across config modules.
# Mutate as attribute assignment (state.ACTIVE_CHORD = ...) — never
# rebind via `from lib.state import ACTIVE_CHORD` (that copies the value).

ACTIVE_CHORD: str | None = None
BAR_MODE: str = "top"  # "top" or "bottom"
passthrough_active: bool = False
FLOAT_STATES: dict = {}
