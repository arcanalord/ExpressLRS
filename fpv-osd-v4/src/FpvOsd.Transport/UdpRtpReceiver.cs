using System.Net;
using System.Net.Sockets;
using FpvOsd.Protocol;

namespace FpvOsd.Transport;

public sealed class UdpRtpReceiver : IAsyncDisposable
{
    private readonly IPAddress _bindAddress;
    private readonly int _requestedPort;
    private UdpClient? _udp;
    private CancellationTokenSource? _stopCts;
    private Task? _receiveLoop;

    public UdpRtpReceiver(int port, IPAddress? bindAddress = null)
    {
        if (port is < 0 or > 65_535) throw new ArgumentOutOfRangeException(nameof(port));
        _requestedPort = port;
        _bindAddress = bindAddress ?? IPAddress.Any;
    }

    public bool IsRunning => _receiveLoop is { IsCompleted: false };
    public int LocalPort { get; private set; }

    public event Action<RtpPacket>? PacketReceived;
    public event Action<int>? MalformedDatagram;
    public event Action<Exception>? Faulted;

    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (_udp is not null) throw new InvalidOperationException("Receiver is already started.");
        _udp = new UdpClient(new IPEndPoint(_bindAddress, _requestedPort));
        LocalPort = ((IPEndPoint)_udp.Client.LocalEndPoint!).Port;
        _stopCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        _receiveLoop = ReceiveLoopAsync(_udp, _stopCts.Token);
        return Task.CompletedTask;
    }

    public async Task StopAsync()
    {
        var udp = _udp;
        var cts = _stopCts;
        var loop = _receiveLoop;
        if (udp is null) return;

        _udp = null;
        _stopCts = null;
        _receiveLoop = null;
        cts?.Cancel();
        udp.Dispose();

        if (loop is not null)
        {
            try { await loop.ConfigureAwait(false); }
            catch (OperationCanceledException) { }
            catch (ObjectDisposedException) { }
        }

        cts?.Dispose();
        LocalPort = 0;
    }

    private async Task ReceiveLoopAsync(UdpClient udp, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var result = await udp.ReceiveAsync(cancellationToken).ConfigureAwait(false);
                if (RtpParser.TryParse(result.Buffer, out var packet)) PacketReceived?.Invoke(packet);
                else MalformedDatagram?.Invoke(result.Buffer.Length);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested) { }
        catch (Exception ex) { Faulted?.Invoke(ex); }
    }

    public async ValueTask DisposeAsync() => await StopAsync().ConfigureAwait(false);
}
