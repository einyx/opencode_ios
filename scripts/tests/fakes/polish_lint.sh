#!/bin/bash
# Runner tests isolate lint just as they isolate Xcode and the simulator.
exit "${MOCK_LINT_EXIT:-0}"
