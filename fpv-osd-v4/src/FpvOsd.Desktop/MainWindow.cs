using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using FpvOsd.Core;

namespace FpvOsd.Desktop;

public sealed class MainWindow : Window
{
    private readonly AppState _state = new();

    private readonly Button _visibleButton = new() { Content = "Visible" };
    private readonly Button _thermalButton = new() { Content = "Thermal" };
    private readonly Button _pipButton = new() { Content = "PiP" };
    private readonly Button _recordButton = new() { Content = "● REC" };
    private readonly Button _settingsButton = new() { Content = "Настройки" };
    private readonly Button _reconnectButton = new() { Content = "Переподключить" };

    private readonly TextBlock _streamStatus = new();
    private readonly TextBlock _motionStatus = new();
    private readonly TextBlock _recordingStatus = new();
    private readonly TextBlock _videoStatus = new();
    private readonly TextBlock _leftTelemetry = new();
    private readonly TextBlock _midTelemetry = new();
    private readonly TextBlock _rightTelemetry = new();
    private readonly TextBlock _pipLabel = new();
    private readonly TextBlock _motionTitle = new();
    private readonly TextBlock _motionDetail = new();

    private readonly VideoSurface _videoSurface = new();
    private readonly Border _pipPanel = new();
    private readonly Border _motionPanel = new();
    private readonly Border _alertBanner = new();
    private readonly Border _settingsDrawer = new();
    private readonly Border _settingsScrim = new();

    private DateTimeOffset? _recordingStartedAt;
    private readonly DispatcherTimer _recordingTimer = new() { Interval = TimeSpan.FromSeconds(1) };

    public MainWindow()
    {
        Title = "FPV OSD v4";
        Width = 1440;
        Height = 900;
        MinWidth = 960;
        MinHeight = 640;
        Background = Brush("#0B0D0F");

        _visibleButton.Click += (_, _) => _state.SelectStream(StreamKind.Visible);
        _thermalButton.Click += (_, _) => _state.SelectStream(StreamKind.Thermal);
        _pipButton.Click += (_, _) => _state.TogglePip();
        _recordButton.Click += (_, _) => ToggleRecording();
        _settingsButton.Click += (_, _) => _state.ToggleSettings();
        _reconnectButton.Click += (_, _) => _state.RequestReconnect();

        _state.Changed += RefreshState;
        _recordingTimer.Tick += (_, _) => RefreshRecordingClock();
        _recordingTimer.Start();

        Content = BuildRoot();
        RefreshState();
    }

    private Control BuildRoot()
    {
        var root = new Grid
        {
            RowDefinitions = new RowDefinitions("Auto,*"),
            Background = Brush("#0B0D0F")
        };

        root.Children.Add(BuildTopBar());

        var body = new Grid
        {
            Margin = new Thickness(14, 4, 14, 14)
        };
        Grid.SetRow(body, 1);
        body.Children.Add(BuildVideoArea());
        body.Children.Add(_settingsScrim);
        body.Children.Add(_settingsDrawer);

        root.Children.Add(body);
        return root;
    }

    private Control BuildTopBar()
    {
        ConfigureButton(_visibleButton, false);
        ConfigureButton(_thermalButton, false);
        ConfigureButton(_pipButton, false);
        ConfigureButton(_recordButton, true);
        ConfigureButton(_settingsButton, false);

        _streamStatus.FontWeight = FontWeight.SemiBold;
        _motionStatus.FontWeight = FontWeight.Medium;
        _recordingStatus.FontWeight = FontWeight.SemiBold;

        var left = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            VerticalAlignment = VerticalAlignment.Center,
            Children =
            {
                Label("FPV OSD v4", 20, FontWeight.SemiBold, "#F2F4F7"),
                Spacer(12),
                _visibleButton,
                _thermalButton,
                _pipButton
            }
        };

        var right = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 14,
            VerticalAlignment = VerticalAlignment.Center,
            Children =
            {
                _streamStatus,
                _motionStatus,
                _recordingStatus,
                _recordButton,
                _settingsButton
            }
        };

        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto")
        };
        grid.Children.Add(left);
        Grid.SetColumn(right, 2);
        grid.Children.Add(right);

        return new Border
        {
            Margin = new Thickness(14, 14, 14, 8),
            Padding = new Thickness(14, 10),
            CornerRadius = new CornerRadius(18),
            Background = Brush("#13151A"),
            Child = grid
        };
    }

    private Control BuildVideoArea()
    {
        var overlay = new Grid();
        overlay.Children.Add(_videoSurface);

        _videoStatus.FontSize = 16;
        _videoStatus.FontWeight = FontWeight.Medium;
        _videoStatus.Foreground = Brush("#8F969F");
        _videoStatus.HorizontalAlignment = HorizontalAlignment.Center;
        _videoStatus.VerticalAlignment = VerticalAlignment.Center;
        _videoStatus.TextAlignment = TextAlignment.Center;
        overlay.Children.Add(_videoStatus);

        BuildPip();
        overlay.Children.Add(_pipPanel);

        BuildMotionPanel();
        overlay.Children.Add(_motionPanel);

        BuildAlertBanner();
        overlay.Children.Add(_alertBanner);

        var bottom = BuildBottomStatus();
        bottom.VerticalAlignment = VerticalAlignment.Bottom;
        bottom.Margin = new Thickness(16, 0, 16, 16);
        overlay.Children.Add(bottom);

        ConfigureButton(_reconnectButton, false);
        _reconnectButton.HorizontalAlignment = HorizontalAlignment.Center;
        _reconnectButton.VerticalAlignment = VerticalAlignment.Center;
        _reconnectButton.Margin = new Thickness(0, 100, 0, 0);
        overlay.Children.Add(_reconnectButton);

        return overlay;
    }

    private void BuildPip()
    {
        _pipLabel.FontSize = 12;
        _pipLabel.FontWeight = FontWeight.SemiBold;
        _pipLabel.Foreground = Brush("#E1E5EC");

        var pipText = Label("PiP", 22, FontWeight.SemiBold, "#555B64");
        pipText.HorizontalAlignment = HorizontalAlignment.Center;
        pipText.VerticalAlignment = VerticalAlignment.Center;

        var grid = new Grid();
        grid.Children.Add(pipText);
        grid.Children.Add(_pipLabel);
        _pipLabel.Margin = new Thickness(14, 12, 0, 0);
        _pipLabel.HorizontalAlignment = HorizontalAlignment.Left;
        _pipLabel.VerticalAlignment = VerticalAlignment.Top;

        _pipPanel.Width = 320;
        _pipPanel.Height = 180;
        _pipPanel.HorizontalAlignment = HorizontalAlignment.Right;
        _pipPanel.VerticalAlignment = VerticalAlignment.Top;
        _pipPanel.Margin = new Thickness(0, 22, 22, 0);
        _pipPanel.CornerRadius = new CornerRadius(16);
        _pipPanel.Background = Brush("#0F1115");
        _pipPanel.BorderBrush = Brush("#2E3138");
        _pipPanel.BorderThickness = new Thickness(1);
        _pipPanel.Child = grid;
    }

    private void BuildMotionPanel()
    {
        _motionTitle.FontSize = 12;
        _motionTitle.FontWeight = FontWeight.SemiBold;
        _motionTitle.Foreground = Brush("#BCC2CC");

        _motionDetail.FontSize = 12;
        _motionDetail.Foreground = Brush("#84D497");

        var stack = new StackPanel
        {
            Spacing = 4,
            Children = { _motionTitle, _motionDetail }
        };

        _motionPanel.Width = 250;
        _motionPanel.HorizontalAlignment = HorizontalAlignment.Left;
        _motionPanel.VerticalAlignment = VerticalAlignment.Top;
        _motionPanel.Margin = new Thickness(22);
        _motionPanel.Padding = new Thickness(14, 10);
        _motionPanel.CornerRadius = new CornerRadius(14);
        _motionPanel.Background = Brush("#1C1F24");
        _motionPanel.Child = stack;
    }

    private void BuildAlertBanner()
    {
        var text = Label("●  ДВИЖЕНИЕ В ЦЕНТРАЛЬНОЙ ЗОНЕ", 14, FontWeight.SemiBold, "#FFE7E7");
        text.HorizontalAlignment = HorizontalAlignment.Center;

        _alertBanner.Width = 420;
        _alertBanner.HorizontalAlignment = HorizontalAlignment.Center;
        _alertBanner.VerticalAlignment = VerticalAlignment.Top;
        _alertBanner.Margin = new Thickness(0, 24, 0, 0);
        _alertBanner.Padding = new Thickness(16);
        _alertBanner.CornerRadius = new CornerRadius(14);
        _alertBanner.Background = Brush("#8C0F14");
        _alertBanner.Child = text;
    }

    private Border BuildBottomStatus()
    {
        ConfigureStatusText(_leftTelemetry);
        ConfigureStatusText(_midTelemetry);
        ConfigureStatusText(_rightTelemetry);
        _rightTelemetry.FontWeight = FontWeight.SemiBold;

        var grid = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,Auto,*")
        };
        grid.Children.Add(_leftTelemetry);
        Grid.SetColumn(_midTelemetry, 1);
        grid.Children.Add(_midTelemetry);
        Grid.SetColumn(_rightTelemetry, 2);
        _rightTelemetry.HorizontalAlignment = HorizontalAlignment.Right;
        grid.Children.Add(_rightTelemetry);

        return new Border
        {
            Padding = new Thickness(14, 12),
            CornerRadius = new CornerRadius(12),
            Background = Brush("#0E1014"),
            Child = grid
        };
    }

    private void BuildSettingsDrawer()
    {
        _settingsScrim.Background = new SolidColorBrush(Color.FromArgb(90, 0, 0, 0));
        _settingsScrim.IsVisible = false;
        _settingsScrim.PointerPressed += (_, _) => _state.SetSettingsOpen(false);

        var close = new Button { Content = "Закрыть" };
        ConfigureButton(close, false);
        close.Click += (_, _) => _state.SetSettingsOpen(false);

        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        header.Children.Add(Label("Настройки", 22, FontWeight.SemiBold, "#F2F4F7"));
        Grid.SetColumn(close, 1);
        header.Children.Add(close);

        var content = new StackPanel
        {
            Spacing = 14,
            Children =
            {
                header,
                Section("Видео"),
                Row("Visible", "Auto decoder"),
                Row("Thermal", "Auto decoder"),
                Section("Звук"),
                Row("Входящий звук", _state.IncomingAudioMuted ? "ВЫКЛ" : "ВКЛ"),
                Row("Звук тревоги", _state.MotionAudioEnabled ? "ВКЛ" : "ВЫКЛ"),
                Section("Center Motion"),
                Row("Чувствительность", "Нормальная"),
                Row("Зона", "Средняя"),
                Section("Диагностика"),
                Row("Decoder", "Auto"),
                Row("FPS", "—"),
                Row("Packet loss", "—"),
                Row("Reconnects", "0"),
                Label("Показать расширенную диагностику", 13, FontWeight.Medium, "#5A9CFF")
            }
        };

        _settingsDrawer.Width = 420;
        _settingsDrawer.HorizontalAlignment = HorizontalAlignment.Right;
        _settingsDrawer.VerticalAlignment = VerticalAlignment.Stretch;
        _settingsDrawer.Margin = new Thickness(0);
        _settingsDrawer.Padding = new Thickness(24);
        _settingsDrawer.CornerRadius = new CornerRadius(20);
        _settingsDrawer.Background = Brush("#13151A");
        _settingsDrawer.Child = new ScrollViewer { Content = content };
        _settingsDrawer.IsVisible = false;
    }

    private void RefreshState()
    {
        if (!Dispatcher.UIThread.CheckAccess())
        {
            Dispatcher.UIThread.Post(RefreshState);
            return;
        }

        if (_settingsDrawer.Child is null)
            BuildSettingsDrawer();

        _visibleButton.IsEnabled = _state.Primary != StreamKind.Visible;
        _thermalButton.IsEnabled = _state.Primary != StreamKind.Thermal;
        _pipButton.Content = _state.PipEnabled ? "PiP: ВКЛ" : "PiP";

        _streamStatus.Text = _state.Connection switch
        {
            ConnectionState.Playing => "● VIDEO",
            ConnectionState.Recovering => "● RECOVERING",
            ConnectionState.Error => "● ERROR",
            ConnectionState.Disconnected => "● OFFLINE",
            _ => "● CONNECTING"
        };
        _streamStatus.Foreground = _state.Connection switch
        {
            ConnectionState.Playing => Brush("#61DB89"),
            ConnectionState.Recovering => Brush("#EDB84C"),
            ConnectionState.Error => Brush("#FF5B5F"),
            _ => Brush("#8F969F")
        };

        _motionStatus.Text = _state.MotionEnabled ? "Движение: ВКЛ" : "Движение: ВЫКЛ";
        _motionStatus.Foreground = Brush("#C6CBD3");
        _recordingStatus.Text = _state.Recording ? "REC · идёт запись" : "Запись: готова";
        _recordingStatus.Foreground = _state.Recording ? Brush("#FF6669") : Brush("#C6CBD3");
        _recordButton.Content = _state.Recording ? "■ Стоп" : "● REC";

        _pipPanel.IsVisible = _state.PipEnabled && _state.Connection == ConnectionState.Playing;
        _pipLabel.Text = _state.PipStream.ToString().ToUpperInvariant();

        _motionPanel.IsVisible = _state.MotionEnabled && _state.Connection == ConnectionState.Playing;
        _motionTitle.Text = "CENTER MOTION";
        _motionDetail.Text = _state.Motion.Triggered ? "ДВИЖЕНИЕ ОБНАРУЖЕНО" : "Мониторинг активен";
        _motionDetail.Foreground = _state.Motion.Triggered ? Brush("#FFC6C7") : Brush("#84D497");
        _motionPanel.Background = _state.Motion.Triggered ? Brush("#941116") : Brush("#1C1F24");
        _alertBanner.IsVisible = _state.MotionEnabled && _state.Motion.Triggered && _state.Connection == ConnectionState.Playing;
        _videoSurface.BorderBrush = _alertBanner.IsVisible ? Brush("#F22E33") : null;
        _videoSurface.BorderThickness = _alertBanner.IsVisible ? new Thickness(3) : new Thickness(0);

        _settingsScrim.IsVisible = _state.SettingsOpen;
        _settingsDrawer.IsVisible = _state.SettingsOpen;

        UpdateConnectionPresentation();
        RefreshTelemetry();
        RefreshRecordingClock();
    }

    private void UpdateConnectionPresentation()
    {
        var primary = _state.Primary.ToString().ToUpperInvariant();
        switch (_state.Connection)
        {
            case ConnectionState.Playing:
                _videoStatus.IsVisible = false;
                _reconnectButton.IsVisible = false;
                break;

            case ConnectionState.Recovering:
                _videoStatus.Text = "ВОССТАНОВЛЕНИЕ ВИДЕО…";
                _videoStatus.Foreground = Brush("#EDB84C");
                _videoStatus.IsVisible = true;
                _reconnectButton.IsVisible = true;
                _pipPanel.IsVisible = false;
                _motionPanel.IsVisible = false;
                break;

            case ConnectionState.Error:
                _videoStatus.Text = "НЕТ ВИДЕО\nПроверьте источник или подключение";
                _videoStatus.Foreground = Brush("#FF6669");
                _videoStatus.IsVisible = true;
                _reconnectButton.IsVisible = true;
                _pipPanel.IsVisible = false;
                _motionPanel.IsVisible = false;
                break;

            case ConnectionState.Disconnected:
                _videoStatus.Text = "ВИДЕО ОТКЛЮЧЕНО";
                _videoStatus.Foreground = Brush("#8F969F");
                _videoStatus.IsVisible = true;
                _reconnectButton.IsVisible = true;
                _pipPanel.IsVisible = false;
                _motionPanel.IsVisible = false;
                break;

            default:
                _videoStatus.Text = $"{primary}  •  ПОДКЛЮЧЕНИЕ ВИДЕО…";
                _videoStatus.Foreground = Brush("#8F969F");
                _videoStatus.IsVisible = true;
                _reconnectButton.IsVisible = false;
                break;
        }
    }

    private void RefreshTelemetry()
    {
        var t = _state.Telemetry;
        var resolution = t.Width > 0 && t.Height > 0 ? $"{t.Width}×{t.Height}" : "—";
        var fps = t.Fps > 0 ? $"{t.Fps:0.0} FPS" : "— FPS";
        _leftTelemetry.Text = $"{_state.Primary}   •   {resolution}   •   {fps}";

        _midTelemetry.Text = _state.Connection == ConnectionState.Recovering
            ? $"Последний кадр  {t.LastFrameAgeMs / 1000d:0.0} c назад   •   попытка {t.ReconnectAttempt}/{Math.Max(1, t.ReconnectMax)}"
            : $"Signal  {t.SignalPercent}%   •   Loss  {t.PacketLossPercent:0.0}%";
    }

    private void ToggleRecording()
    {
        _state.ToggleRecording();
        _recordingStartedAt = _state.Recording ? DateTimeOffset.UtcNow : null;
        RefreshRecordingClock();
    }

    private void RefreshRecordingClock()
    {
        if (!_state.Recording || _recordingStartedAt is null)
        {
            _rightTelemetry.Text = "REC  00:00:00";
            _rightTelemetry.Foreground = Brush("#8F969F");
            return;
        }

        var elapsed = DateTimeOffset.UtcNow - _recordingStartedAt.Value;
        _rightTelemetry.Text = $"REC  {elapsed:hh\\:mm\\:ss}";
        _rightTelemetry.Foreground = Brush("#FF6669");
    }

    private static void ConfigureButton(Button button, bool danger)
    {
        button.Padding = new Thickness(14, 9);
        button.CornerRadius = new CornerRadius(12);
        button.Background = danger ? Brush("#A51C21") : Brush("#1D2026");
        button.Foreground = Brush("#F2F4F7");
        button.BorderThickness = new Thickness(0);
    }

    private static void ConfigureStatusText(TextBlock text)
    {
        text.FontSize = 13;
        text.FontWeight = FontWeight.Medium;
        text.Foreground = Brush("#C2C8D1");
        text.VerticalAlignment = VerticalAlignment.Center;
    }

    private static TextBlock Label(string text, double size, FontWeight weight, string color) =>
        new()
        {
            Text = text,
            FontSize = size,
            FontWeight = weight,
            Foreground = Brush(color),
            VerticalAlignment = VerticalAlignment.Center
        };

    private static Control Spacer(double width) => new Border { Width = width };

    private static TextBlock Section(string text) =>
        Label(text, 13, FontWeight.SemiBold, "#8792A3");

    private static Control Row(string label, string value)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        grid.Children.Add(Label(label, 14, FontWeight.Medium, "#E0E4EA"));
        var right = Label(value, 13, FontWeight.Medium, "#A3AAB4");
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        return grid;
    }

    private static IBrush Brush(string hex) => SolidColorBrush.Parse(hex);
}
