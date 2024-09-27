import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: CameraScreen(camera: camera),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({super.key, required this.camera});

  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true, // Enable classification for smile detection
    ),
  );
  List<Face> _faces = [];
  bool _isDetecting = false;
  bool _isFaceDetectionEnabled = true;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    _initializeControllerFuture = _controller.initialize().then((_) {
      _controller.startImageStream((CameraImage image) {
        if (_isFaceDetectionEnabled && !_isDetecting) {
          _isDetecting = true;
          detectFaces(image).then((_) {
            _isDetecting = false;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  InputImageRotation _rotationIntToImageRotation(int rotation) {
    switch (rotation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Future<void> detectFaces(CameraImage image) async {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final ui.Size imageSize = ui.Size(image.width.toDouble(), image.height.toDouble());
      final InputImageRotation imageRotation = _rotationIntToImageRotation(widget.camera.sensorOrientation);

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: inputImageData,
      );

      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          _faces = faces;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error detecting faces: $e')),
        );
      }
    }
  }

  void _toggleFaceDetection() {
    setState(() {
      _isFaceDetectionEnabled = !_isFaceDetectionEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-Time Face Detection'),
        actions: [
          IconButton(
            icon: Icon(_isFaceDetectionEnabled ? Icons.pause : Icons.play_arrow),
            onPressed: _toggleFaceDetection,
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller),
                CustomPaint(
                  painter: FacePainter(_faces, _controller.value.previewSize!, _controller.value.aspectRatio),
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Text(
                    'Faces detected: ${_faces.length}',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final ui.Size imageSize;
  final double aspectRatio;

  FacePainter(this.faces, this.imageSize, this.aspectRatio);

  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    for (var face in faces) {
      final rect = _scaleRect(
        rect: face.boundingBox,
        imageSize: imageSize,
        widgetSize: size,
        aspectRatio: aspectRatio,
      );
      canvas.drawRect(rect, paint);

      if (face.smilingProbability != null && face.smilingProbability! > 0.5) {
        final smilePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = Colors.green;
        canvas.drawRect(rect, smilePaint);
      }
    }
  }

  Rect _scaleRect({
    required Rect rect,
    required ui.Size imageSize,
    required ui.Size widgetSize,
    required double aspectRatio,
  }) {
    final double scaleX = widgetSize.width / imageSize.height;
    final double scaleY = widgetSize.height / imageSize.width;

    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
