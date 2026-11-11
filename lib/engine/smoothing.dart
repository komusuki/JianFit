/// Plain moving average of the last [n] values (Shared Formula Document,
/// Smoothing). While fewer than [n] values are stored, it averages what it has.
class MovingAverage {
  MovingAverage(this.n);

  final int n;
  final List<double> _buffer = [];

  double add(double value) {
    _buffer.add(value);
    if (_buffer.length > n) _buffer.removeAt(0);
    return _buffer.reduce((a, b) => a + b) / _buffer.length;
  }

  void reset() => _buffer.clear();
}
