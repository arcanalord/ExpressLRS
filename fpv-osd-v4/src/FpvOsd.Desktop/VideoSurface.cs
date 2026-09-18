using System;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using FpvOsd.Platform.Abstractions;

namespace FpvOsd.Desktop;

public sealed class VideoSurface : Border, IDisposable
{
    private readonly Image _image = new()
    {
        Stretch = Stretch.Uniform,
        HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Stretch,
        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Stretch
    };

    private readonly TextBlock _status = new()
    {
        Foreground = Brushes.White,
        FontSize = 18,
        TextAlignment = TextAlignment.Center,
        HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Center,
        VerticalAlignment = Avalonia.Layout.VerticalAlignment.Center
    };

    private WriteableBitmap? _bitmap;
    private bool _hasFrame;

    public VideoSurface()
    {
        Background = Brushes.Black;
        CornerRadius = new CornerRadius(12);
        Child = new Grid
        {
            Children = { _image, _status }
        };
        ShowStatus("Подключение видео…");
    }

    public void Present(VideoFrame frame)
    {
        if (frame.Width <= 0 || frame.Height <= 0)
            return;

        var required = checked(frame.Width * frame.Height * 4);
        if (frame.Bgra32.Length < required)
            return;

        var bytes = frame.Bgra32[..required].ToArray();
        Dispatcher.UIThread.Post(() => PresentOnUiThread(frame.Width, frame.Height, bytes));
    }

    public void ShowStatus(string text)
    {
        Dispatcher.UIThread.Post(() =>
        {
            if (_hasFrame)
                return;

            _status.Text = text;
            _status.IsVisible = true;
            _image.IsVisible = false;
        });
    }

    public void Clear(string status = "Нет видео")
    {
        Dispatcher.UIThread.Post(() =>
        {
            _hasFrame = false;
            _image.IsVisible = false;
            _status.Text = status;
            _status.IsVisible = true;
        });
    }

    private void PresentOnUiThread(int width, int height, byte[] bgra)
    {
        if (_bitmap is null || _bitmap.PixelSize.Width != width || _bitmap.PixelSize.Height != height)
        {
            _bitmap?.Dispose();
            _bitmap = new WriteableBitmap(
                new PixelSize(width, height),
                new Vector(96, 96),
                PixelFormats.Bgra8888,
                AlphaFormat.Opaque);
            _image.Source = _bitmap;
        }

        using var framebuffer = _bitmap.Lock();
        var sourceStride = checked(width * 4);

        if (framebuffer.RowBytes == sourceStride)
        {
            Marshal.Copy(bgra, 0, framebuffer.Address, checked(sourceStride * height));
        }
        else
        {
            for (var row = 0; row < height; row++)
            {
                Marshal.Copy(
                    bgra,
                    row * sourceStride,
                    IntPtr.Add(framebuffer.Address, row * framebuffer.RowBytes),
                    sourceStride);
            }
        }

        _hasFrame = true;
        _status.IsVisible = false;
        _image.IsVisible = true;
    }

    public void Dispose()
    {
        _bitmap?.Dispose();
        _bitmap = null;
    }
}
