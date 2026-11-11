# MP7 model fidelity: compares two capture sets of MP7ModelFidelityTest.capture (same 36 states, same viewport).
# Per state: visible-weapon mask = max channel |phase1 - phase2| >= 8/255 (the weapon's parts hidden in phase 2), the
# mask IoU between the sets, and the mean absolute RGB difference of phase 1 inside the union of the two masks.
# Usage: powershell -File compare_capture_sets.ps1 -A <dir> -B <dir> [-Out <csv>]
param([string]$A, [string]$B, [string]$Out = "")
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public class CmpSets {
  static byte[] Load(string p, out int w, out int h) {
    using (Bitmap b = new Bitmap(p)) {
      w = b.Width; h = b.Height;
      BitmapData d = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      byte[] a = new byte[d.Stride * h]; Marshal.Copy(d.Scan0, a, 0, a.Length); b.UnlockBits(d); return a;
    }
  }
  public static double[] Compare(string a1, string a2, string b1, string b2) {
    int w, h, w2, h2;
    byte[] A1 = Load(a1, out w, out h), A2 = Load(a2, out w, out h), B1 = Load(b1, out w2, out h2), B2 = Load(b2, out w2, out h2);
    if (w != w2 || h != h2) return new double[] { -1, 0, 0, 0, 0 };
    long inter = 0, uni = 0, na = 0, nb = 0; double diff = 0;
    for (int i = 0; i < w * h; i++) {
      int o = i * 4;
      int da = Math.Max(Math.Abs(A1[o] - A2[o]), Math.Max(Math.Abs(A1[o + 1] - A2[o + 1]), Math.Abs(A1[o + 2] - A2[o + 2])));
      int db = Math.Max(Math.Abs(B1[o] - B2[o]), Math.Max(Math.Abs(B1[o + 1] - B2[o + 1]), Math.Abs(B1[o + 2] - B2[o + 2])));
      bool ma = da >= 8, mb = db >= 8;
      if (ma) na++; if (mb) nb++;
      if (ma && mb) inter++;
      if (ma || mb) { uni++; diff += (Math.Abs(A1[o] - B1[o]) + Math.Abs(A1[o + 1] - B1[o + 1]) + Math.Abs(A1[o + 2] - B1[o + 2])) / 3.0; }
    }
    return new double[] { uni > 0 ? (double)inter / uni : 1, na, nb, uni > 0 ? diff / uni : 0, uni };
  }
}
"@
$rows = @()
for ($i = 1; $i -le 36; $i++) {
  $s = "s{0:D3}" -f $i
  $r = [CmpSets]::Compare("$A\${s}_p1.png", "$A\${s}_p2.png", "$B\${s}_p1.png", "$B\${s}_p2.png")
  $rows += [pscustomobject]@{ state = $i; iou = [math]::Round($r[0], 4); weaponPxA = $r[1]; weaponPxB = $r[2]; meanAbsDiffInWeapon = [math]::Round($r[3], 2) }
}
if ($Out) { $rows | Export-Csv -NoTypeInformation $Out }
$rows
$m = ($rows | Measure-Object iou -Average -Minimum); $d = ($rows | Measure-Object meanAbsDiffInWeapon -Average -Maximum)
"mask IoU mean {0:N4} min {1:N4}; mean |RGB diff| inside the weapon mean {2:N2} max {3:N2}" -f $m.Average, $m.Minimum, $d.Average, $d.Maximum
