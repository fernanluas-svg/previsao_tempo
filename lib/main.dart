import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
void main() async {
  await dotenv.load();
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

class _PrevisaoTelaState extends State<PrevisaoTela> {
  String temperatura = "Buscando...";
  String condicao = "Carregando...";
  String nomeCidade = "Localização";
  String iconeUrl = "";
  String erro = "";
  bool carregando = true;
  bool _usandoGPS = true;
  final TextEditingController _cidadeController = TextEditingController();

  // ⚠️ COLOQUE SUA CHAVE AQUI ⚠️
  final String apiKey = dotenv.env['400e544615c312ca26618731c0a93650'] ?? '';

  @override
  void initState() {
    super.initState();
    _pegarClimaPorGPS();
  }

  @override
  void dispose() {
    _cidadeController.dispose();
    super.dispose();
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
      setState(() {
        temperatura = data['main']['temp'].toStringAsFixed(0) + "°C";
        condicao = data['weather'][0]['description'].toLowerCase();
        nomeCidade = data['name'];
        iconeUrl =
            "https://openweathermap.org/img/wn/${data['weather'][0]['icon']}@2x.png";
        carregando = false;
      });
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

  Widget _buildClimaAnimado() {
    bool isChuva = condicao.contains('chuva') || condicao.contains('chuvas');
    bool isNublado = condicao.contains('nublado') || condicao.contains('nuvens');
    bool isTempestade = condicao.contains('trovoada') || condicao.contains('tempestade');
    bool isNeve = condicao.contains('neve');
    bool isCeuLimpo = condicao.contains('céu limpo') || condicao.contains('ensolarado');
    bool isVento = condicao.contains('vento');

    double tamanho = 120;

    return SizedBox(
      width: tamanho,
      height: tamanho,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // SOL
          if (isCeuLimpo)
            Container(
              width: tamanho,
              height: tamanho,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.amber, Colors.orange],
                  radius: 0.7,
                ),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .scale(
                  duration: const Duration(seconds: 3),
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1.1, 1.1),
                )
                .then()
                .animate(
                  onPlay: (controller) => controller.repeat(),
                )
                .rotate(
                  duration: const Duration(seconds: 10),
                  begin: 0,
                  end: 6.28,
                ),

          // RAIOS DE SOL
          if (isCeuLimpo)
            Container(
              width: tamanho * 1.6,
              height: tamanho * 1.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.amber.withOpacity(0.3),
                    Colors.transparent,
                  ],
                  radius: 0.5,
                ),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .scale(
                  duration: const Duration(seconds: 2),
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1.2, 1.2),
                ),

          // CHUVA (CORRIGIDO: sem o parâmetro 'end')
          if (isChuva)
            ...List.generate(
              15,
              (index) => Container(
                width: 3,
                height: 15,
                color: Colors.blue.withOpacity(0.6),
              )
                  .animate(delay: Duration(milliseconds: index * 100))
                  .moveY(
                    duration: const Duration(milliseconds: 600),
                    begin: -60,
                    end: 60,
                    curve: Curves.linear,
                  )
                  .fadeOut(
                    duration: const Duration(milliseconds: 600),
                    begin: 1,
                  )
                  .then()
                  .animate(onPlay: (controller) => controller.repeat())
                  .moveX(
                    duration: const Duration(milliseconds: 200),
                    begin: index % 2 == 0 ? -5 : 5,
                    end: index % 2 == 0 ? 5 : -5,
                    curve: Curves.easeInOut,
                  ),
            ),

          // NUVENS
          if (isNublado || isChuva || isTempestade)
            Icon(
              Icons.cloud,
              size: tamanho * 0.8,
              color: isTempestade
                  ? Colors.grey[800]
                  : Colors.white.withOpacity(0.9),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .moveX(
                  duration: const Duration(seconds: 4),
                  begin: -20,
                  end: 20,
                  curve: Curves.easeInOut,
                ),

          // TEMPESTADE (RAIOS) - CORRIGIDO
          if (isTempestade)
            Icon(
              Icons.flash_on,
              size: tamanho * 0.5,
              color: Colors.yellow[700],
            )
                .animate(onPlay: (controller) => controller.repeat())
                .fadeIn(
                  duration: const Duration(milliseconds: 100),
                )
                .then(delay: const Duration(milliseconds: 200))
                .fadeOut(duration: const Duration(milliseconds: 100))
                .then(delay: const Duration(milliseconds: 300))
                .fadeIn(
                  duration: const Duration(milliseconds: 100),
                )
                .then(delay: const Duration(milliseconds: 150))
                .fadeOut(duration: const Duration(milliseconds: 100)),

          // NEVE
          if (isNeve)
            ...List.generate(
              20,
              (index) => Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              )
                  .animate(delay: Duration(milliseconds: index * 80))
                  .moveY(
                    duration: const Duration(milliseconds: 1000),
                    begin: -80,
                    end: 80,
                    curve: Curves.linear,
                  )
                  .then()
                  .animate(onPlay: (controller) => controller.repeat())
                  .moveX(
                    duration: const Duration(milliseconds: 300),
                    begin: -10,
                    end: 10,
                    curve: Curves.easeInOut,
                  ),
            ),

          // VENTO
          if (isVento)
            ...List.generate(
              5,
              (index) => Container(
                width: 40 + index * 10,
                height: 3,
                color: Colors.white.withOpacity(0.3),
              )
                  .animate(delay: Duration(milliseconds: index * 150))
                  .moveX(
                    duration: const Duration(milliseconds: 800),
                    begin: -50,
                    end: 50,
                    curve: Curves.easeInOut,
                  )
                  .then()
                  .animate(onPlay: (controller) => controller.repeat())
                  .moveY(
                    duration: const Duration(milliseconds: 400),
                    begin: -10 + index * 8,
                    end: 10 + index * 8,
                    curve: Curves.easeInOut,
                  ),
            ),

          // ÍCONE BASE
          if (iconeUrl.isNotEmpty)
            Image.network(
              iconeUrl,
              width: tamanho * 0.6,
              height: tamanho * 0.6,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            )
                .animate()
                .fadeIn(duration: const Duration(milliseconds: 500)),
        ],
      ),
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
            colors: condicao.contains("chuva")
                ? [Colors.blueGrey[900]!, Colors.blueGrey[700]!]
                : condicao.contains("nublado")
                    ? [Colors.grey[800]!, Colors.grey[600]!]
                    : condicao.contains("tempestade")
                        ? [Colors.indigo[900]!, Colors.blue[900]!]
                        : condicao.contains("neve")
                            ? [Colors.blueGrey[50]!, Colors.blueGrey[300]!]
                            : [Colors.orange[700]!, Colors.amber[400]!],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                Card(
                  color: Colors.white.withOpacity(0.15),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _cidadeController,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: "Digite o nome da cidade",
                              hintStyle: TextStyle(color: Colors.white70),
                              border: InputBorder.none,
                              icon: Icon(Icons.search, color: Colors.white),
                            ),
                            onSubmitted: (value) {
                              if (value.isNotEmpty) {
                                _pegarClimaPorCidade(value);
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.my_location, color: Colors.white),
                          onPressed: _pegarClimaPorGPS,
                          tooltip: 'Usar minha localização',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                if (!_usandoGPS && nomeCidade.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "🔍 Busca manual",
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 10),

                Expanded(
                  child: Center(
                    child: carregando
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 20),
                              Text("Olhando o céu..."),
                            ],
                          )
                        : erro.isNotEmpty
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 80, color: Colors.orange[300]),
                                  const SizedBox(height: 20),
                                  Text(erro,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 18)),
                                  const SizedBox(height: 30),
                                  ElevatedButton(
                                    onPressed: () {
                                      if (_usandoGPS) {
                                        _pegarClimaPorGPS();
                                      } else {
                                        _pegarClimaPorCidade(_cidadeController.text);
                                      }
                                    },
                                    child: const Text("TENTAR NOVAMENTE"),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildClimaAnimado(),
                                  const SizedBox(height: 20),
                                  Text(
                                    nomeCidade,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    condicao.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      letterSpacing: 2,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    temperatura,
                                    style: const TextStyle(
                                      fontSize: 70,
                                      fontWeight: FontWeight.w200,
                                    ),
                                  ),
                                  const SizedBox(height: 30),
                                  Icon(Icons.location_on, color: Colors.grey[400]),
                                  Text(
                                    _usandoGPS ? "Atualizado agora" : "Buscado manualmente",
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  const SizedBox(height: 20),
                                  TextButton.icon(
                                    onPressed: () {
                                      if (_usandoGPS) {
                                        _pegarClimaPorGPS();
                                      } else {
                                        _pegarClimaPorCidade(_cidadeController.text);
                                      }
                                    },
                                    icon: const Icon(Icons.refresh, color: Colors.white),
                                    label: const Text(
                                      "ATUALIZAR",
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
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