"""Helpers to parse and evaluate IMCCE VSOP87 files (versions B and D share the same text format)."""
import math
import re


def parse_vsop(path):
    """Return {variable: {power: [(amplitude, phase, frequency), ...]}} for variables 1 (L), 2 (B), 3 (R)."""
    series = {}
    with open(path, encoding="ascii") as handle:
        for line in handle:
            if line.startswith(" VSOP87"):
                match = re.search(r"VARIABLE (\d) .*?\*T\*\*(\d)", line)
                variable, power = int(match.group(1)), int(match.group(2))
                current = series.setdefault(variable, {}).setdefault(power, [])
                continue
            fields = line.split()
            # Term lines: iv ip ... 12 multipliers ... S K A B C ; the last three are A, B, C.
            amplitude, phase, frequency = float(fields[-3]), float(fields[-2]), float(fields[-1])
            current.append((amplitude, phase, frequency))
    return series


def evaluate(series, jde):
    """Evaluate heliocentric L (rad), B (rad), R (au) at a Julian Ephemeris Day."""
    t = (jde - 2451545.0) / 365250.0
    values = {}
    for variable, powers in series.items():
        total = 0.0
        for power, terms in powers.items():
            partial = 0.0
            for amplitude, phase, frequency in terms:
                partial += amplitude * math.cos(phase + frequency * t)
            total += partial * t ** power
        values[variable] = total
    return values[1] % (2 * math.pi), values[2], values[3]
