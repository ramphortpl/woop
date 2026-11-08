"""Generates Tests/WoopCoreTests/ZipFixtures.swift: raw DEFLATE streams made by zlib (stored,
fixed, dynamic, RLE blocks; memLevel 1 forces many small blocks) and .zip archives made by
Python's zipfile (regular, streamed with data descriptors, without central directory, nested).
Run: python3 Tools/make_zip_fixtures.py [--zip PATH]   (--zip also writes the sample export there)
"""
import zlib, zipfile, io, base64, sys, os

def text(n):
    # Deterministic CSV-like text, reproducible in Swift.
    lines = ["ts,hr,label"]
    x = 12345
    for i in range(n):
        x = (x * 1103515245 + 12345) % 2147483648
        hr = 50 + (x >> 16) % 120
        lab = ["repos", "course", "sommeil", "vélo", "tennis"][(x >> 8) % 5]
        lines.append(f"{1780000000 + i},{hr},{lab}")
    return ("\n".join(lines) + "\n").encode("utf-8")

def raw(data, level, strategy=zlib.Z_DEFAULT_STRATEGY, mem=9):
    c = zlib.compressobj(level, zlib.DEFLATED, -15, mem, strategy)
    return c.compress(data) + c.flush()

t = text(400)
out = {}
out["dynamic"] = raw(t, 9, mem=1)
out["fast"] = raw(t, 1)
out["fixed"] = raw(t, 6, zlib.Z_FIXED)
out["stored"] = raw(t[:3000], 0)
out["rle"] = raw(t, 6, zlib.Z_RLE, mem=1)
for k, v in out.items():
    print(k, len(v), file=sys.stderr)
print("len", len(t), "crc", hex(zlib.crc32(t)), file=sys.stderr)

cycles = ("Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Skin temp (celsius),Blood oxygen %,Day Strain,Energy burned (cal),Max HR (bpm),Average HR (bpm),Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %\n"
          "2026-11-08 02:31:00,,UTC+01:00,45,58,52,33.4,96.1,12.8,2534,171,79,2026-11-08 02:31:00,2026-11-08 08:24:00,76,15.2,340,353,180,70,90,13,447,60,96,71\n"
          "2026-11-06 23:10:00,2026-11-08 02:31:00,UTC+01:00,68,54,61,33.2,96.5,9.4,2310,160,74,2026-11-06 23:10:00,2026-11-07 07:05:00,92,14.8,450,475,240,95,115,25,489,20,95,80\n")
workouts = ("Cycle start time,Cycle end time,Cycle timezone,Workout start time,Workout end time,Duration (min),Activity name,Activity Strain,Energy burned (cal),Max HR (bpm),Average HR (bpm),HR Zone 1 %,HR Zone 2 %,HR Zone 3 %,HR Zone 4 %,HR Zone 5 %,GPS enabled\n"
            "2026-11-08 02:31:00,,UTC+01:00,2026-11-08 09:24:00,2026-11-08 11:50:00,146,Cycling,12.6,1350,171,135,10,30,40,15,5,false\n"
            "2026-11-08 02:31:00,,UTC+01:00,2026-11-08 14:38:00,2026-11-08 15:18:00,40,Padel,4.1,240,120,105,60,30,10,0,0,false\n"
            "2026-11-07 02:31:00,,UTC+01:00,2026-11-07 18:00:00,2026-11-07 19:00:00,60,Table Tennis,6.0,400,150,120,20,30,30,15,5,false\n")
sleeps = ("Cycle start time,Cycle end time,Cycle timezone,Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min),Light sleep duration (min),Deep (SWS) duration (min),REM duration (min),Awake duration (min),Sleep need (min),Sleep debt (min),Sleep efficiency %,Sleep consistency %,Nap\n"
          "2026-11-08 02:31:00,,UTC+01:00,2026-11-08 13:00:00,2026-11-08 13:40:00,,,35,40,30,5,0,5,,,88,,true\n")
journal = "Cycle start time,Cycle end time,Cycle timezone,Question text,Answered yes,Notes\n2026-11-08 02:31:00,,UTC+01:00,Alcool ?,false,\n"

def mkzip(stream=False):
    buf = io.BytesIO()
    class NS(io.RawIOBase):
        def __init__(self): self.b = bytearray()
        def writable(self): return True
        def write(self, d): self.b += d; return len(d)
        def seekable(self): return False
        def tell(self): raise OSError
    target = NS() if stream else buf
    when = (2026, 11, 8, 8, 24, 0)  # fixed, so the fixtures are reproducible
    def entry(name, data, method=zipfile.ZIP_DEFLATED):
        info = zipfile.ZipInfo(name, date_time=when)
        info.compress_type = method
        z.writestr(info, data)
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        entry("my_whoop_data_2026_11_08/", "", zipfile.ZIP_STORED)
        entry("my_whoop_data_2026_11_08/physiological_cycles.csv", cycles)
        entry("my_whoop_data_2026_11_08/workouts.csv", workouts)
        entry("my_whoop_data_2026_11_08/sleeps.csv", sleeps)
        entry("my_whoop_data_2026_11_08/journal_entries.csv", journal, zipfile.ZIP_STORED)
        entry("__MACOSX/my_whoop_data_2026_11_08/._workouts.csv", b"\x00\x05\x16\x07binary junk")
    return bytes(target.b if stream else buf.getvalue())

zipA = mkzip(False)
zipB = mkzip(True)
print("zipA", len(zipA), "zipB", len(zipB), file=sys.stderr)
# Data-descriptor flag check
print("zipB flags", zipB[6], file=sys.stderr)
# truncated: drop central directory
cd = zipA.rfind(b"PK\x01\x02")
first_cd = zipA.find(b"PK\x01\x02")
zipC = zipA[:first_cd]
# nested zip: outer zip storing zipA
nb = io.BytesIO()
with zipfile.ZipFile(nb, "w", zipfile.ZIP_STORED) as z:
    z.writestr(zipfile.ZipInfo("export.zip", date_time=(2026, 11, 8, 8, 24, 0)), zipA)
zipD = nb.getvalue()

def b64(name, data):
    s = base64.b64encode(data).decode()
    chunks = [s[i:i+100] for i in range(0, len(s), 100)]
    return f'    static let {name} = """\n' + "\n".join("    " + c for c in chunks) + '\n    """\n'

with open(os.path.join(os.path.dirname(__file__), "..", "Tests", "WoopCoreTests", "ZipFixtures.swift"), "w") as f:
    f.write("import Foundation\n\n/// Generated by Tools/make_zip_fixtures.py (zlib + Python zipfile).\nenum ZipFixtures {\n")
    for k, v in out.items():
        f.write(b64(k, v))
    f.write(b64("zipA", zipA))
    f.write(b64("zipStreamed", zipB))
    f.write(b64("zipNoCentral", zipC))
    f.write(b64("zipNested", zipD))
    f.write(f"    static let textLength = {len(t)}\n")
    f.write(f"    static let textCRC: UInt32 = 0x{zlib.crc32(t):08X}\n")
    f.write(f"    static let storedLength = {len(t[:3000])}\n")
    f.write("}\n")

if "--zip" in sys.argv:
    with open(sys.argv[sys.argv.index("--zip") + 1], "wb") as f:
        f.write(zipA)

