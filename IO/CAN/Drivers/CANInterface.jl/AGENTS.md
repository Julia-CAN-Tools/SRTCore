# CANInterface Agent Instructions

Follow the workspace `../../../../AGENTS.md`. This package is the hardware boundary: raw
Linux SocketCAN sockets, frame layouts, filters, timeouts, and deterministic close.

- Keep C-compatible struct layouts and validate standard/extended IDs and DLC.
- Preserve idempotent close and clean interruption of blocking reads.
- A package-load check is offline:
  `julia --project=. -e 'using CANInterface'`.
- The test suite may open and transmit on `vcan0`/`vcan1`; run it only after
  verifying those interfaces are kernel `vcan` devices. Use
  `../scripts/hil-workspace full-virtual`.
- Never test against a physical CAN interface without explicit approval.
