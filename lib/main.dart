import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:getwidget/getwidget.dart';
import 'package:latlong2/latlong.dart' hide Path;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Previsão do Tempo',
      theme: ThemeData.dark(),
      home: const PrevisaoTela(),
    );
  }
}

class PrevisaoTela extends StatefulWidget {
  const PrevisaoTela({super.key});

  @override
  State<PrevisaoTela> createState() => _PrevisaoTelaState();
}

class _PrevisaoTelaState extends State<PrevisaoTela>
    with TickerProviderStateMixin {
  late final MapController _mapController = MapController();
  String temperatura = "Buscando...";
  String condicao = "Carregando...";
  String nomeCidade = "Localização";
  String iconeUrl = "";
  String erro = "";
  String humidade = "--";
  String vento = "--";
  String nascerSol = "--";
  String porSol = "--";
  int aqi = 0;
  String aqiLabel = "--";
  double _tempNum = 0;
  int _humidityNum = 0;
  double _windMps = 0;
  List<Map<String, dynamic>> _previsaoHoras = [];
  double _precipitacao = 0;
  double? _latitude;
  double? _longitude;
  bool carregando = true;
  bool _usandoGPS = true;
  String _mapaAtivo = 'vento';
  List<_FocoChuva> _focosChuva = [];
  LatLngBounds? _boundsAtual;
  Set<int>? _idsVisiveis;
  double _zoomAtual = 7.0;
  final TextEditingController _cidadeController = TextEditingController();

  bool get _tempestade =>
      condicao.contains('trovoada') || condicao.contains('tempestade');

  bool get _temPrecipitacaoReal =>
      _precipitacao > 0 ||
      condicao.contains('chuva') ||
      condicao.contains('chuvas') ||
      condicao.contains('trovoada') ||
      condicao.contains('tempestade') ||
      condicao.contains('granizo');

  List<_FocoChuva> get _focosVisiveis {
    final ids = _idsVisiveis;
    if (ids == null) return _focosChuva;
    final ordenados = ids.toList()..sort();
    return [for (final i in ordenados) _focosChuva[i]];
  }

  void _atualizarFocosVisiveis() {
    final bounds = _boundsAtual;
    if (bounds == null) return;
    final ids = <int>{};
    for (var i = 0; i < _focosChuva.length; i++) {
      if (bounds.contains(_focosChuva[i].posicao)) ids.add(i);
    }
    final antigos = _idsVisiveis ?? const <int>{};
    if (antigos.length != ids.length) {
      _idsVisiveis = ids;
      setState(() {});
      return;
    }
    for (final i in ids) {
      if (!antigos.contains(i)) {
        _idsVisiveis = ids;
        setState(() {});
        return;
      }
    }
  }

  static const String apiKey = String.fromEnvironment('API_KEY');

  @override
  void initState() {
    super.initState();
    _pegarClimaPorGPS();
  }

  @override
  void dispose() {
    _cidadeController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _animarZoom(double delta) async {
    final camera = _mapController.camera;
    final alvo = (camera.zoom + delta)
        .clamp(camera.minZoom ?? 3.0, camera.maxZoom ?? 19.0);
    if (alvo == camera.zoom) return;

    final inicio = camera.zoom;
    final centro = camera.center;
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    final anim = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    controller.addListener(() {
      _mapController.move(
        centro,
        inicio + (alvo - inicio) * anim.value,
      );
    });
    await controller.forward();
    controller.dispose();
  }

  List<Color> _getGradient() {
    final bool isDay = iconeUrl.contains('d@2x.png');
    if (isDay) {
      return const [Color(0xFF0D47A1), Color(0xFF42A5F5)];
    }
    return const [Color(0xFF030614), Color(0xFF0A1B4D)];
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _pegarClimaPorGPS() async {
    setState(() {
      carregando = true;
      erro = "";
      _usandoGPS = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception("Ative o GPS do celular.");

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception("Permissão de localização negada.");
        }
      }

      Position posicao = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);

      String url =
          "https://api.openweathermap.org/data/2.5/weather?lat=${posicao.latitude}&lon=${posicao.longitude}&appid=$apiKey&units=metric&lang=pt_br";

      await _buscarClima(url);
    } catch (e) {
      setState(() {
        erro = e.toString().replaceFirst("Exception: ", "");
        carregando = false;
      });
    }
  }

  Future<void> _pegarClimaPorCidade(String cidade) async {
    if (cidade.isEmpty) {
      setState(() => erro = "Digite o nome de uma cidade.");
      return;
    }

    setState(() {
      carregando = true;
      erro = "";
      _usandoGPS = false;
    });

    try {
      String url =
          "https://api.openweathermap.org/data/2.5/weather?q=$cidade&appid=$apiKey&units=metric&lang=pt_br";
      await _buscarClima(url);
    } catch (e) {
      setState(() {
        erro = e.toString().replaceFirst("Exception: ", "");
        carregando = false;
      });
    }
  }

  Future<void> _buscarClima(String url) async {
    var response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      _latitude = data['coord']['lat'];
      _longitude = data['coord']['lon'];

      DateTime nascer =
          DateTime.fromMillisecondsSinceEpoch(data['sys']['sunrise'] * 1000)
              .toLocal();
      DateTime por =
          DateTime.fromMillisecondsSinceEpoch(data['sys']['sunset'] * 1000)
              .toLocal();

      final rain = data['rain'];
      double precipitacao = 0;
      if (rain is Map<String, dynamic>) {
        precipitacao =
            ((rain['1h'] ?? rain['3h']) ?? 0).toDouble();
      }

      setState(() {
        temperatura = data['main']['temp'].toStringAsFixed(0) + "°C";
        condicao = data['weather'][0]['description'].toLowerCase();
        nomeCidade = data['name'];
        iconeUrl =
            "https://openweathermap.org/img/wn/${data['weather'][0]['icon']}@2x.png";
        humidade = "${data['main']['humidity']}%";
        vento = "${data['wind']['speed'].toStringAsFixed(1)} m/s";
        nascerSol =
            "${nascer.hour.toString().padLeft(2, '0')}:${nascer.minute.toString().padLeft(2, '0')}";
        porSol =
            "${por.hour.toString().padLeft(2, '0')}:${por.minute.toString().padLeft(2, '0')}";
        _tempNum = (data['main']['temp'] as num).toDouble();
        _humidityNum = data['main']['humidity'];
        _windMps = (data['wind']['speed'] as num).toDouble();
        _precipitacao = precipitacao;
        carregando = false;
      });
      _focosChuva = _gerarFocosChuva();
      _idsVisiveis = null;
      _boundsAtual = null;
      _zoomAtual = 7.0;
      _pegarPrevisaoHoras();
      _buscarQualidadeAr();
    } else if (response.statusCode == 404) {
      setState(() {
        erro = "Cidade não encontrada.";
        carregando = false;
      });
    } else {
      setState(() {
        erro = "Erro ao buscar dados: ${response.statusCode}";
        carregando = false;
      });
    }
  }

  Future<void> _pegarPrevisaoHoras() async {
    if (_latitude == null || _longitude == null) return;

    try {
      String url =
          "https://api.openweathermap.org/data/2.5/forecast?lat=$_latitude&lon=$_longitude&appid=$apiKey&units=metric&lang=pt_br";
      var response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        List<dynamic> lista = data['list'];
        List<Map<String, dynamic>> proximas = [];

        for (var item in lista) {
          if (proximas.length >= 5) break;
          DateTime itemDt = DateTime.parse(item['dt_txt']);
          if (itemDt
              .isAfter(DateTime.now().subtract(const Duration(hours: 2)))) {
            String hora = "${itemDt.hour.toString().padLeft(2, '0')}:00";
            String temp = "${item['main']['temp'].toStringAsFixed(0)}°";
            String icon = item['weather'][0]['icon'];
            String iconUrl =
                "https://openweathermap.org/img/wn/$icon@2x.png";
            proximas.add({
              'hora': hora,
              'temperatura': temp,
              'iconeUrl': iconUrl,
            });
          }
        }

        setState(() {
          _previsaoHoras = proximas;
        });
      }
    } catch (_) {}
  }

  Future<void> _buscarQualidadeAr() async {
    if (_latitude == null || _longitude == null) return;

    try {
      var response = await http.get(Uri.parse(
          "http://api.openweathermap.org/data/2.5/air_pollution?lat=$_latitude&lon=$_longitude&appid=$apiKey"));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        int valor = data['list'][0]['main']['aqi'];
        List<String> labels = const [
          "",
          "Bom",
          "Moderado",
          "Ruim para grupos sensíveis",
          "Ruim",
          "Muito Ruim"
        ];
        setState(() {
          aqi = valor;
          aqiLabel = labels[valor];
        });
      }
    } catch (_) {}
  }

  Map<String, dynamic> _getEsportesIndex() {
    double tempC = _tempNum;
    int hum = _humidityNum;
    double windKmh = _windMps * 3.6;
    bool temChuva = condicao.contains('chuva') || condicao.contains('chuvas');
    bool tempestade =
        condicao.contains('trovoada') || condicao.contains('tempestade');
    bool neve = condicao.contains('neve');

    if (tempC < 5 ||
        tempC > 35 ||
        tempestade ||
        neve ||
        windKmh > 40 ||
        (temChuva && tempestade))
      return {"label": "Ruim para atividades", "cor": Colors.red[300]!};

    if ((tempC >= 15 && tempC <= 25) &&
        (hum >= 40 && hum <= 70) &&
        windKmh < 15 &&
        !temChuva)
      return {"label": "Ótimo para correr!", "cor": Colors.green[300]!};

    if ((tempC >= 10 && tempC <= 30) &&
        (hum >= 30 && hum <= 80) &&
        windKmh < 25 &&
        !temChuva)
      return {"label": "Bom para atividades", "cor": Colors.lightGreen[300]!};

    return {"label": "Médio, tome cuidado", "cor": Colors.orange[300]!};
  }

  int getMoonPhase(DateTime date) {
    DateTime knownNewMoon = DateTime(2000, 1, 6, 18, 14);
    double daysSince = date.difference(knownNewMoon).inHours / 24.0;
    double phase = (daysSince % 29.53058867) / 29.53058867;
    return (phase * 8).floor() % 8;
  }

  Widget _buildSearchBarCompacta() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: GFTextField(
                  controller: _cidadeController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Digite a cidade",
                    hintStyle: TextStyle(color: Colors.white60, fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onFieldSubmitted: (value) {
                    if (value.isNotEmpty) _pegarClimaPorCidade(value);
                  },
                ),
              ),
              if (!_usandoGPS && nomeCidade.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    "📍",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 10,
                    ),
                  ),
                ),
              InkWell(
                onTap: _pegarClimaPorGPS,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.my_location, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapaClimatico() {
    if (_latitude == null || _longitude == null) {
      return _buildGlassCard(
        padding: const EdgeInsets.all(8),
        child: const Center(
          child: Text(
            "Mapa\nindisponível",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ),
      );
    }

    bool tempestade =
        condicao.contains('trovoada') || condicao.contains('tempestade');
    bool temPrecipitacaoReal = _precipitacao > 0 ||
        condicao.contains('chuva') ||
        condicao.contains('chuvas') ||
        condicao.contains('trovoada') ||
        condicao.contains('tempestade') ||
        condicao.contains('granizo');

    double intensidade = 0;
    if (tempestade) {
      intensidade = 0.85;
    } else if (_precipitacao > 0) {
      intensidade = (_precipitacao / 6.0).clamp(0.3, 1.0);
    } else if (condicao.contains('forte') ||
        condicao.contains('intensa') ||
        condicao.contains('muito')) {
      intensidade = 1.0;
    } else if (condicao.contains('garoa') || condicao.contains('leve')) {
      intensidade = 0.3;
    } else if (temPrecipitacaoReal) {
      intensidade = 0.6;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(_latitude!, _longitude!),
              initialZoom: 7.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (camera, hasGesture) {
                _boundsAtual = camera.visibleBounds;
                _zoomAtual = camera.zoom;
                _atualizarFocosVisiveis();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.previsao_tempo',
              ),
              if (_mapaAtivo == 'chuva')
                TileLayer(
                  urlTemplate:
                      'https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png?appid=$apiKey',
                  userAgentPackageName: 'com.example.previsao_tempo',
                ),
              if (_mapaAtivo == 'vento')
                TileLayer(
                  urlTemplate:
                      'https://tile.openweathermap.org/map/wind_new/{z}/{x}/{y}.png?appid=$apiKey',
                  userAgentPackageName: 'com.example.previsao_tempo',
                ),
              if (_mapaAtivo == 'temp')
                TileLayer(
                  urlTemplate:
                      'https://tile.openweathermap.org/map/temp_new/{z}/{x}/{y}.png?appid=$apiKey',
                  userAgentPackageName: 'com.example.previsao_tempo',
                ),
              if (_mapaAtivo == 'chuva' && temPrecipitacaoReal)
                PolygonLayer(
                  polygonLabels: false,
                  polygons: [
                    for (final poligono in _gerarPoligonosChuva())
                      Polygon(
                        points: poligono,
                        color: const Color(0xFF5B7BA6)
                            .withOpacity(0.18 + intensidade * 0.10),
                        borderColor:
                            const Color(0xFFA9C3E8).withOpacity(0.45),
                        borderStrokeWidth: 1.5,
                      ),
                  ],
                ),
              if (_mapaAtivo == 'chuva' && temPrecipitacaoReal)
                MarkerLayer(
                  markers: [
                    for (final foco in _focosVisiveis)
                      Marker(
                        point: foco.posicao,
                        width: _tamanhoFoco(),
                        height: _tamanhoFoco(),
                        alignment: Alignment.center,
                        child: _FocoChuvaMarker(
                          intensidade: foco.intensidade,
                          tempestade: foco.tempestade,
                        ),
                      ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map, color: Colors.white70, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    switch (_mapaAtivo) {
                      'vento' => "Vento",
                      'chuva' => "Chuva",
                      'temp' => "Temp",
                      _ => "Base",
                    },
                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            right: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLayerChip("💨", "Vento", _mapaAtivo == 'vento', () {
                  _selecionarCamada('vento');
                }),
                const SizedBox(width: 6),
                _buildLayerChip("🌧️", "Chuva", _mapaAtivo == 'chuva', () {
                  _selecionarCamada('chuva');
                }),
                const SizedBox(width: 6),
                _buildLayerChip("🌡️", "Temp", _mapaAtivo == 'temp', () {
                  _selecionarCamada('temp');
                }),
              ],
            ),
          ),
          Positioned(
            right: 8,
            bottom: 44,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _botaoZoom(Icons.add, () => _animarZoom(1)),
                const SizedBox(height: 8),
                _botaoZoom(Icons.remove, () => _animarZoom(-1)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<List<LatLng>> _gerarPoligonosChuva() {
    if (_latitude == null || _longitude == null) return const [];

    final seed =
        (_latitude! * 10000 + _longitude! * 10000).abs().round() & 0x7fffffff;
    final rng = Random(seed);

    List<LatLng> blob(double latCentro, double lngCentro, double raioBase) {
      const int n = 40;
      final pontos = <LatLng>[];
      final cosLat = cos(latCentro * pi / 180);
      for (var i = 0; i < n; i++) {
        final ang = (i / n) * 2 * pi;
        final raioLat = raioBase * (0.75 + rng.nextDouble() * 0.5);
        final raioLng = raioLat / cosLat;
        pontos.add(LatLng(
          latCentro + sin(ang) * raioLat,
          lngCentro + cos(ang) * raioLng,
        ));
      }
      return pontos;
    }

    final centroLat = _latitude!;
    final centroLng = _longitude!;

    return [
      blob(centroLat, centroLng, 0.4),
      blob(centroLat + 0.30, centroLng + 0.45, 0.24),
    ];
  }

  List<_FocoChuva> _gerarFocosChuva() {
    if (_latitude == null || _longitude == null || !_temPrecipitacaoReal) {
      return const [];
    }

    final seed = (_latitude! * 10000 + _longitude! * 10000).abs().round() &
        0x7fffffff;
    final rng = Random(seed);
    final lat = _latitude!;
    final lng = _longitude!;
    final cosLat = cos(lat * pi / 180);
    final focos = <_FocoChuva>[];

    const int n = 12;
    for (var i = 0; i < n; i++) {
      final ang = (i / n) * 2 * pi + rng.nextDouble() * 0.4;
      final raio = 0.15 + rng.nextDouble() * 0.4;
      final distNorm = raio / 0.55;
      final intensidade =
          (1 - distNorm * 0.6 - rng.nextDouble() * 0.2).clamp(0.25, 1.0);
      focos.add(_FocoChuva(
        LatLng(lat + sin(ang) * raio, lng + cos(ang) * raio / cosLat),
        intensidade,
        _tempestade && intensidade > 0.7 && (i % 3 == 0),
      ));
    }

    focos.add(_FocoChuva(LatLng(lat, lng), 1.0, _tempestade));
    return focos;
  }

  void _selecionarCamada(String camada) {
    setState(() {
      _mapaAtivo = _mapaAtivo == camada ? '' : camada;
    });
  }

  double _tamanhoFoco() => (30 + _zoomAtual * 3).clamp(44, 96);

  Widget _botaoZoom(IconData icone, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.85),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.6)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icone, color: Colors.black87, size: 22),
        ),
      ),
    );
  }

  Widget _buildLayerChip(
      String emoji, String label, bool ativo, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ativo ? const Color(0xFF2563EB) : Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: ativo ? Colors.white.withOpacity(0.4) : Colors.white.withOpacity(0.1),
          ),
          boxShadow: ativo
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withOpacity(0.4),
                    blurRadius: 10,
                  ),
                ]
              : null,
        ),
        child: Text(
          "$emoji $label",
          style: TextStyle(
            fontSize: 9,
            color: ativo ? Colors.white : Colors.white60,
            fontWeight: ativo ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildListaPrevisao() {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _previsaoHoras.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          var item = _previsaoHoras[index];
          return GFCard(
            color: Colors.white.withOpacity(0.12),
            elevation: 2,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            content: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item['hora'],
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Image.network(
                  item['iconeUrl'],
                  width: 36,
                  height: 36,
                  errorBuilder: (_, __, ___) => const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.cloud, color: Colors.white70)),
                ),
                const SizedBox(height: 2),
                Text(
                  item['temperatura'],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimacaoGrande() {
    bool isDay = iconeUrl.contains('d@2x.png');
    bool isChuva = condicao.contains('chuva') || condicao.contains('chuvas');
    bool isNublado =
        condicao.contains('nublado') || condicao.contains('nuvens');
    bool isTempestade =
        condicao.contains('trovoada') || condicao.contains('tempestade');
    bool isNeve = condicao.contains('neve');
    bool isCeuLimpo =
        condicao.contains('céu limpo') || condicao.contains('ensolarado');
    bool isVento = condicao.contains('vento');
    bool mostrarPassaros = condicao.isNotEmpty &&
        !condicao.contains('chuva') &&
        !condicao.contains('chuvas') &&
        !condicao.contains('trovoada') &&
        !condicao.contains('tempestade') &&
        !condicao.contains('neve') &&
        !condicao.contains('granizo');
    int moonPhase = getMoonPhase(DateTime.now());
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double w = constraints.maxWidth;
              double h = constraints.maxHeight;
              final rng = Random(42);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  if (!isDay)
                    ...List.generate(60, (i) {
                      double sx = rng.nextDouble();
                      double sy = rng.nextDouble();
                      double starSize = 0.5 + rng.nextDouble() * 2.5;
                      int delayMs = (rng.nextDouble() * 8000).floor();
                      double baseOpacity = 0.4 + rng.nextDouble() * 0.6;
                      bool hasGlow = rng.nextDouble() > 0.7;
                      return Positioned(
                        left: sx * w,
                        top: sy * h,
                        child: Container(
                          width: starSize,
                          height: starSize,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(baseOpacity),
                            shape: BoxShape.circle,
                            boxShadow: hasGlow
                                ? [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.5),
                                      blurRadius: starSize * 2,
                                    ),
                                  ]
                                : null,
                          ),
                        )
                            .animate(
                                delay: Duration(milliseconds: delayMs))
                            .fadeOut(
                              duration: Duration(
                                  milliseconds: 600 +
                                      (rng.nextDouble() * 2500).floor()),
                              curve: Curves.easeInOut,
                            )
                            .then()
                            .animate(onPlay: (c) => c.repeat())
                            .fadeIn(
                              duration: Duration(
                                  milliseconds: 600 +
                                      (rng.nextDouble() * 2500).floor()),
                              curve: Curves.easeInOut,
                            )
                            .then()
                            .animate(onPlay: (c) => c.repeat())
                            .fadeOut(
                              duration: Duration(
                                  milliseconds: 600 +
                                      (rng.nextDouble() * 2500).floor()),
                              curve: Curves.easeInOut,
                            ),
                      );
                    }),

                  if (mostrarPassaros) ...[
                    _buildPassaro(
                      color: Colors.white,
                      top: h * 0.12,
                      size: 22,
                      duration: const Duration(seconds: 16),
                      leftToRight: true,
                      width: w,
                      flapDelay: const Duration(milliseconds: 0),
                    ),
                    _buildPassaro(
                      color: Colors.white,
                      top: h * 0.27,
                      size: 27,
                      duration: const Duration(seconds: 21),
                      leftToRight: true,
                      width: w,
                      flapDelay: const Duration(milliseconds: 120),
                    ),
                    _buildPassaro(
                      color: Colors.black87,
                      top: h * 0.17,
                      size: 20,
                      duration: const Duration(seconds: 15),
                      leftToRight: false,
                      width: w,
                      flapDelay: const Duration(milliseconds: 60),
                    ),
                    _buildPassaro(
                      color: Colors.black87,
                      top: h * 0.33,
                      size: 25,
                      duration: const Duration(seconds: 19),
                      leftToRight: false,
                      width: w,
                      flapDelay: const Duration(milliseconds: 180),
                    ),
                  ],

                  if (!isDay)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: SizedBox(
                        width: 52,
                        height: 52,
                        child: CustomPaint(
                          painter: MoonPhasePainter(moonPhase),
                        ),
                      ),
                    ),

                  if (isDay && isCeuLimpo)
                    Positioned(
                      top: h * 0.08,
                      left: w * 0.1,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Colors.amber, Colors.orange],
                            radius: 0.7,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.4),
                              blurRadius: 40,
                              spreadRadius: 15,
                            ),
                          ],
                        ),
                      )
                          .animate(onPlay: (c) => c.repeat())
                          .scale(
                            duration: const Duration(seconds: 3),
                            begin: const Offset(0.9, 0.9),
                            end: const Offset(1.1, 1.1),
                          ),
                    ),

                  ...List.generate(isNublado ? 5 : 3, (i) {
                    double top = [0.08, 0.28, 0.48, 0.12, 0.38][i % 5];
                    double size = [65.0, 80.0, 55.0, 90.0, 70.0][i % 5];
                    double opacity = [0.35, 0.7, 0.25, 0.5, 0.9][i % 5];
                    double speed = [8.0, 10.0, 7.0, 12.0, 9.0][i % 5];
                    bool reverse = i.isOdd;
                    Color cloudColor =
                        isTempestade ? Colors.grey[700]! : Colors.white;
                    return Positioned(
                      top: top * h,
                      child: Icon(
                        Icons.cloud,
                        size: size,
                        color: cloudColor
                            .withOpacity(isTempestade ? 0.55 : opacity),
                      )
                          .animate(onPlay: (c) => c.repeat())
                          .moveX(
                            duration: Duration(seconds: speed.round()),
                            begin: reverse
                                ? w + size * 1.5 + (i * 15)
                                : -size * 1.5 - (i * 15),
                            end: reverse
                                ? -size * 1.5 - (i * 15)
                                : w + size * 1.5 + (i * 15),
                            curve: Curves.linear,
                          ),
                    );
                  }),

                  if (isChuva)
                    ...List.generate(18, (i) {
                      double leftPos = (rng.nextDouble() * 0.9 + 0.05) * w;
                      return Positioned(
                        top: 0,
                        left: leftPos,
                        child: Container(
                          width: 2,
                          height: 12,
                          color: Colors.blue.withOpacity(0.5),
                        )
                            .animate(delay: Duration(
                                milliseconds:
                                    (rng.nextDouble() * 2000).floor()))
                            .moveY(
                              duration: const Duration(milliseconds: 450),
                              begin: -20,
                              end: h + 20,
                              curve: Curves.linear,
                            )
                            .fadeOut(
                              duration: const Duration(milliseconds: 450),
                              begin: 0.8,
                            )
                            .then()
                            .animate(onPlay: (c) => c.repeat())
                            .moveX(
                              duration: const Duration(milliseconds: 120),
                              begin: i % 2 == 0 ? -3 : 3,
                              end: i % 2 == 0 ? 3 : -3,
                              curve: Curves.easeInOut,
                            ),
                      );
                    }),

                  if (isTempestade)
                    Positioned(
                      left: w * 0.4,
                      top: h * 0.2,
                      child: Icon(
                        Icons.flash_on,
                        size: 32,
                        color: Colors.yellow[700],
                      )
                          .animate(onPlay: (c) => c.repeat())
                          .fadeIn(duration: const Duration(milliseconds: 80))
                          .then(delay: const Duration(milliseconds: 150))
                          .fadeOut(duration: const Duration(milliseconds: 80))
                          .then(delay: const Duration(milliseconds: 400))
                          .fadeIn(duration: const Duration(milliseconds: 80))
                          .then(delay: const Duration(milliseconds: 100))
                          .fadeOut(duration: const Duration(milliseconds: 80)),
                    ),

                  if (isNeve)
                    ...List.generate(20, (i) {
                      double leftPos = (rng.nextDouble() * 0.9 + 0.05) * w;
                      return Positioned(
                        top: 0,
                        left: leftPos,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        )
                            .animate(delay: Duration(
                                milliseconds:
                                    (rng.nextDouble() * 3000).floor()))
                            .moveY(
                              duration: const Duration(milliseconds: 800),
                              begin: -10,
                              end: h + 10,
                              curve: Curves.linear,
                            )
                            .then()
                            .animate(onPlay: (c) => c.repeat())
                            .moveX(
                              duration: const Duration(milliseconds: 200),
                              begin: -6,
                              end: 6,
                              curve: Curves.easeInOut,
                            ),
                      );
                    }),

                  if (isVento)
                    ...List.generate(4, (i) {
                      double topPos = 0.15 + (i * 0.16);
                      double width = 40 + rng.nextDouble() * 35;
                      return Positioned(
                        top: topPos * h,
                        left: 0,
                        child: Container(
                          width: width,
                          height: 2,
                          color: Colors.white.withOpacity(0.2),
                        )
                            .animate(delay: Duration(milliseconds: i * 200))
                            .moveX(
                              duration: const Duration(milliseconds: 600),
                              begin: -width,
                              end: w + width,
                              curve: Curves.easeInOut,
                            )
                            .then()
                            .animate(onPlay: (c) => c.repeat())
                            .moveY(
                              duration: const Duration(milliseconds: 250),
                              begin: -3 + i * 5,
                              end: 3 + i * 5,
                              curve: Curves.easeInOut,
                            ),
                      );
                    }),

                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          temperatura,
                          style: const TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w200,
                            height: 1.05,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          condicao.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 2,
                            color: Colors.white.withOpacity(0.85),
                            shadows: const [
                              Shadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on,
                                color: Colors.white70, size: 12),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                nomeCidade,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  if (iconeUrl.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Image.network(
                        iconeUrl,
                        width: 36,
                        height: 36,
                        errorBuilder: (_, __, ___) => const SizedBox(),
                      )
                          .animate()
                          .fadeIn(duration: const Duration(milliseconds: 500)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPassaro({
    required Color color,
    required double top,
    required double size,
    required Duration duration,
    required bool leftToRight,
    required double width,
    Duration flapDelay = Duration.zero,
  }) {
    const Duration flapPhase = Duration(milliseconds: 110);

    return Positioned(
      top: top,
      left: leftToRight ? -size : width,
      child: SizedBox(
        width: size,
        height: size * 0.7,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              painter: BirdPainter(color: color, flap: 0.0),
            ),
            CustomPaint(
              painter: BirdPainter(color: color, flap: 1.0),
            )
                .animate(
                  delay: flapDelay,
                  onPlay: (c) => c.repeat(),
                )
                .fadeIn(
                  duration: flapPhase,
                  curve: Curves.easeInOut,
                )
                .then()
                .fadeOut(
                  duration: flapPhase,
                  curve: Curves.easeInOut,
                ),
          ],
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .moveX(
            duration: duration,
            begin: leftToRight ? -size : width + size,
            end: leftToRight ? width + size : -size,
            curve: Curves.linear,
          )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(
            duration: Duration(milliseconds: (700 + size * 10).round()),
            begin: -6.0,
            end: 6.0,
            curve: Curves.easeInOut,
          ),
    );
  }

  Widget _buildInfoRow() {
    return Row(
      children: [
        _infoCard(Icons.water_drop, "Umidade", humidade),
        const SizedBox(width: 8),
        _infoCard(Icons.air, "Vento", vento),
        const SizedBox(width: 8),
        _infoCard(Icons.wb_sunny, "Nascer do Sol", nascerSol),
        const SizedBox(width: 8),
        _infoCard(Icons.nights_stay, "Pôr do Sol", porSol),
      ],
    );
  }

  Widget _infoCard(IconData icone, String label, String valor) {
    return Expanded(
      child: GFCard(
        color: Colors.white.withOpacity(0.12),
        elevation: 2,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: Colors.white70, size: 16),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: const TextStyle(fontSize: 9, color: Colors.white60),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              valor,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEsportesAQIRow() {
    var esportes = _getEsportesIndex();
    return Row(
      children: [
        Expanded(
          child: GFCard(
            color: Colors.white.withOpacity(0.12),
            elevation: 2,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            content: GFListTile(
              avatar: const Text("🏃‍♂️", style: TextStyle(fontSize: 24)),
              title: const Text(
                "Esportes",
                style: TextStyle(fontSize: 11, color: Colors.white60),
              ),
              subTitle: Text(
                esportes['label'],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: esportes['cor'],
                ),
              ),
              padding: const EdgeInsets.all(8),
              margin: EdgeInsets.zero,
            ),
          ),
        ),
        if (aqi > 0) ...[
          const SizedBox(width: 10),
          Expanded(
            child: GFCard(
              color: Colors.white.withOpacity(0.12),
              elevation: 2,
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              content: GFListTile(
                avatar: const Text("🌿", style: TextStyle(fontSize: 24)),
                title: const Text(
                  "Qualidade do Ar",
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
                subTitle: Text(
                  aqiLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                margin: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _getGradient(),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: carregando
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 20),
                        Text("Olhando o céu..."),
                      ],
                    ),
                  )
                : erro.isNotEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline,
                                size: 80, color: Colors.orange[300]),
                            const SizedBox(height: 20),
                            Text(erro,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 18)),
                            const SizedBox(height: 30),
                            GFButton(
                              text: "TENTAR NOVAMENTE",
                              onPressed: () {
                                if (_usandoGPS) {
                                  _pegarClimaPorGPS();
                                } else {
                                  _pegarClimaPorCidade(
                                      _cidadeController.text);
                                }
                              },
                              color: Colors.orange.shade400,
                              textColor: Colors.black87,
                              shape: GFButtonShape.pills,
                              size: GFSize.LARGE,
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          _buildSearchBarCompacta(),
                          const SizedBox(height: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 300,
                                    child: Row(
                                      children: [
                                        Expanded(
                                            child: _buildAnimacaoGrande()),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: _buildMapaClimatico()),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(),
                                  const SizedBox(height: 12),
                                  _buildEsportesAQIRow(),
                                  if (_previsaoHoras.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    const Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        "Previsão por Hora",
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _buildListaPrevisao(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

class MoonPhasePainter extends CustomPainter {
  final int phase;
  MoonPhasePainter(this.phase);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
    final center = Offset(cx, cy);
    final moonColor = const Color(0xFFF5F3CE);
    final darkColor = const Color(0xFF1A1A2E);

    final glowPaint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);
    canvas.drawCircle(center, r * 1.4, glowPaint);

    final glowPaint2 = Paint()
      ..color = moonColor.withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawCircle(center, r * 2, glowPaint2);

    canvas.drawCircle(center, r, Paint()..color = moonColor);

    if (phase == 0) {
      canvas.drawCircle(center, r, Paint()..color = darkColor);
      return;
    }
    if (phase == 4) return;

    final isWaxing = phase < 4;
    final terminatorX = cx + r * cos(phase * pi / 4);
    final hr = (terminatorX - cx).abs() + 0.1;

    final moonPath = Path()..addOval(Rect.fromCircle(center: center, radius: r));

    final regionPath = Path();
    if (isWaxing) {
      regionPath.moveTo(0, cy - r);
      regionPath.lineTo(terminatorX, cy - r);
      regionPath.arcToPoint(
        Offset(terminatorX, cy + r),
        radius: Radius.elliptical(hr, r),
        clockwise: true,
      );
      regionPath.lineTo(0, cy + r);
    } else {
      regionPath.moveTo(size.width, cy - r);
      regionPath.lineTo(terminatorX, cy - r);
      regionPath.arcToPoint(
        Offset(terminatorX, cy + r),
        radius: Radius.elliptical(hr, r),
        clockwise: false,
      );
      regionPath.lineTo(size.width, cy + r);
    }
    regionPath.close();

    final resultPath =
        Path.combine(PathOperation.intersect, moonPath, regionPath);
    canvas.drawPath(resultPath, Paint()..color = darkColor);
  }

  @override
  bool shouldRepaint(covariant MoonPhasePainter oldDelegate) =>
      oldDelegate.phase != phase;
}

class BirdPainter extends CustomPainter {
  final Color color;
  final double flap;

  BirdPainter({required this.color, this.flap = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final double tipY = size.height * (0.30 + 0.30 * flap);
    final double ctrlY = size.height * (0.05 + 0.40 * flap);
    final double bodyY = size.height * 0.50;

    final path = Path()
      ..moveTo(0, tipY)
      ..quadraticBezierTo(
          size.width * 0.25, ctrlY, size.width * 0.5, bodyY)
      ..quadraticBezierTo(
          size.width * 0.75, ctrlY, size.width, tipY);

    canvas.drawPath(path, paint);

    final bodyPaint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.5, bodyY - size.height * 0.10),
      Offset(size.width * 0.5, bodyY + size.height * 0.10),
      bodyPaint,
    );
  }

  @override
  bool shouldRepaint(covariant BirdPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.flap != flap;
}

class _FocoChuva {
  final LatLng posicao;
  final double intensidade;
  final bool tempestade;

  const _FocoChuva(this.posicao, this.intensidade, this.tempestade);
}

class _FocoChuvaMarker extends StatefulWidget {
  final double intensidade;
  final bool tempestade;

  const _FocoChuvaMarker({
    required this.intensidade,
    required this.tempestade,
  });

  @override
  State<_FocoChuvaMarker> createState() => _FocoChuvaMarkerState();
}

class _FocoChuvaMarkerState extends State<_FocoChuvaMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_GotaFoco> _gotas;
  final Random _rng = Random(29);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _gotas = List.generate(14, (_) {
      return _GotaFoco(
        _rng.nextDouble() * 2 - 1,
        0.8 + _rng.nextDouble() * 0.8,
        _rng.nextDouble(),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final blink =
              (sin(t * 2 * pi * 2.5) * 0.5 + 0.5).clamp(0.15, 1.0);
          return LayoutBuilder(
            builder: (context, constraints) {
              final lado = constraints.maxWidth;
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _FocoChuvaPainter(
                      t: t,
                      intensidade: widget.intensidade.clamp(0.0, 1.0),
                      gotas: _gotas,
                    ),
                  ),
                  if (widget.tempestade)
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(top: lado * 0.02),
                        child: Icon(
                          Icons.flash_on,
                          size: lado * 0.4,
                          color: Colors.amber.withOpacity(blink),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _GotaFoco {
  final double x;
  final double vel;
  final double fase;

  const _GotaFoco(this.x, this.vel, this.fase);
}

class _FocoChuvaPainter extends CustomPainter {
  final double t;
  final double intensidade;
  final List<_GotaFoco> gotas;

  _FocoChuvaPainter({
    required this.t,
    required this.intensidade,
    required this.gotas,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final cx = w / 2;
    final cy = h / 2;
    final raio = w / 2;

    final circulo =
        Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: raio));

    canvas.drawPath(
      circulo,
      Paint()
        ..color = const Color(0xFF5B7BA6).withOpacity(0.16 + intensidade * 0.10)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      circulo,
      Paint()
        ..color = const Color(0xFFA9C3E8).withOpacity(0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    canvas.save();
    canvas.clipPath(circulo);

    final n = (gotas.length * intensidade).round().clamp(0, gotas.length);
    final paintGota = Paint()
      ..color = const Color(0xFFCFE5FF).withOpacity(0.6)
      ..strokeWidth = w * 0.02
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < n; i++) {
      final g = gotas[i];
      final progresso = (t * g.vel + g.fase) % 1.0;
      final comprimento = h * 0.16;
      final y = -comprimento + progresso * (h * 1.2 + comprimento);
      final x = cx + g.x * raio * 0.7;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - w * 0.02, y + comprimento),
        paintGota,
      );
    }

    _pintarPoca(canvas, Offset(cx, cy + raio * 0.5), raio);

    canvas.restore();
  }

  void _pintarPoca(Canvas canvas, Offset centro, double raio) {
    final pocaRx = raio * 0.5;
    final pocaRy = pocaRx * 0.45;

    final corpo = Path()
      ..addOval(Rect.fromCenter(
          center: centro, width: pocaRx * 2, height: pocaRy * 2));
    canvas.drawPath(
      corpo,
      Paint()..color = const Color(0xFF3E5A7D).withOpacity(0.45),
    );
    canvas.drawPath(
      corpo,
      Paint()
        ..color = const Color(0xFFBFE0FF).withOpacity(0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    for (var i = 0; i < 3; i++) {
      final prog = (t + i * 0.33) % 1.0;
      final r = prog * pocaRx;
      canvas.drawOval(
        Rect.fromCenter(
            center: centro, width: r * 2, height: r * 2 * (pocaRy / pocaRx)),
        Paint()
          ..color = const Color(0xFFD6EAFF).withOpacity((1 - prog) * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    final paintSplash = Paint()
      ..color = const Color(0xFFD6EAFF).withOpacity(0.7)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final prog = (t * 1.4 + i * 0.25) % 1.0;
      final ang = i * (pi / 2) + pi / 4;
      final d = pocaRx * 0.7 * (0.5 + 0.5 * prog);
      final pos = Offset(
          centro.dx + cos(ang) * d, centro.dy + sin(ang) * d * 0.4);
      canvas.drawLine(pos, Offset(pos.dx, pos.dy - 2 - prog * 4), paintSplash);
    }
  }

  @override
  bool shouldRepaint(covariant _FocoChuvaPainter old) =>
      old.t != t || old.intensidade != intensidade;
}
