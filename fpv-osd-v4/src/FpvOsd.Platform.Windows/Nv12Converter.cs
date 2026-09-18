using System;

namespace FpvOsd.Platform.Windows;

public static class Nv12Converter
{
    public static byte[] ToBgra32(ReadOnlySpan<byte> nv12, int width, int height)
    {
        if (width <= 0 || height <= 0 || (width & 1) != 0 || (height & 1) != 0)
            throw new ArgumentOutOfRangeException(nameof(width), "NV12 dimensions must be positive and even.");

        var yBytes = checked(width * height);
        var required = checked(yBytes + yBytes / 2);
        if (nv12.Length < required)
            throw new ArgumentException($"NV12 buffer is too small. Need {required} bytes, got {nv12.Length}.", nameof(nv12));

        var bgra = new byte[checked(yBytes * 4)];
        var uvOffset = yBytes;

        for (var y = 0; y < height; y++)
        {
            var yRow = y * width;
            var uvRow = uvOffset + (y / 2) * width;

            for (var x = 0; x < width; x++)
            {
                var yy = nv12[yRow + x];
                var uv = uvRow + (x & ~1);
                var u = nv12[uv];
                var v = nv12[uv + 1];

                var c = Math.Max(0, yy - 16);
                var d = u - 128;
                var e = v - 128;

                var r = Clip((298 * c + 409 * e + 128) >> 8);
                var g = Clip((298 * c - 100 * d - 208 * e + 128) >> 8);
                var b = Clip((298 * c + 516 * d + 128) >> 8);

                var dst = (yRow + x) * 4;
                bgra[dst] = (byte)b;
                bgra[dst + 1] = (byte)g;
                bgra[dst + 2] = (byte)r;
                bgra[dst + 3] = 255;
            }
        }

        return bgra;
    }

    private static int Clip(int value) => Math.Clamp(value, 0, 255);
}
