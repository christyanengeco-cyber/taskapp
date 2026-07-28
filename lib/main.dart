import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TaskType { focus, flexible }
enum TaskStatus { pending, done, failed }

// Paleta de 7 cores pré-setadas para filtro futuro
const List<Color> taskColors = [
  Color(0xff4f86f7), // Azul (Padrão)
  Color(0xffe57373), // Vermelho Suave
  Color(0xff81c784), // Verde
  Color(0xffffb74d), // Laranja
  Color(0xffba68c8), // Roxo
  Color(0xff4dd0e1), // Ciano
  Color(0xffa1887f), // Marrom/Cinza
];

class Task {
  Task({
    required this.id,
    required this.title,
    required this.type,
    required this.start,
    required this.color,
    this.minutes = 30,
    this.deadline,
    this.status = TaskStatus.pending,
    this.snoozes = 0,
    this.snoozedUntil,
  });

  String id, title;
  TaskType type;
  DateTime start;
  int color, minutes, snoozes;
  DateTime? deadline, snoozedUntil;
  TaskStatus status;

  DateTime get end => type == TaskType.focus
      ? start.add(Duration(minutes: minutes))
      : (deadline ?? start.add(const Duration(hours: 1)));

  DateTime get alarm => snoozedUntil ?? start;
  bool get failed => status == TaskStatus.failed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.index,
        'start': start.toIso8601String(),
        'color': color,
        'minutes': minutes,
        'deadline': deadline?.toIso8601String(),
        'status': status.index,
        'snoozes': snoozes,
        'snoozedUntil': snoozedUntil?.toIso8601String(),
      };

  static Task fromJson(Map<String, dynamic> j) => Task(
        id: j['id'],
        title: j['title'],
        type: TaskType.values[j['type']],
        start: DateTime.parse(j['start']),
        color: j['color'],
        minutes: j['minutes'] ?? 30,
        deadline: j['deadline'] == null ? null : DateTime.parse(j['deadline']),
        status: TaskStatus.values[j['status'] ?? 0],
        snoozes: j['snoozes'] ?? 0,
        snoozedUntil: j['snoozedUntil'] == null ? null : DateTime.parse(j['snoozedUntil']),
      );
}

class HatchPainter extends CustomPainter {
  final Color color;
  HatchPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    const double spacing = 12.0;
    for (double i = -size.height; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');
  runApp(const FocoApp());
}

class FocoApp extends StatelessWidget {
  const FocoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff4f86f7),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Task> tasks = [];
  DateTime day = DateUtils.dateOnly(DateTime.now());
  Timer? timer;
  DateTime now = DateTime.now();

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        setState(() => now = DateTime.now());
        failSweep();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('tasks');
    if (raw != null) {
      try {
        tasks = (jsonDecode(raw) as List).map((x) => Task.fromJson(x)).toList();
      } catch (_) {
        tasks = [];
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tasks', jsonEncode(tasks.map((x) => x.toJson()).toList()));
  }

  bool get blocked => tasks.any((x) => x.failed);

  List<Task> get today =>
      tasks.where((x) => DateUtils.isSameDay(x.start, day)).toList()..sort((a, b) => a.start.compareTo(b.start));

  void failSweep() {
    bool changed = false;
    for (final t in tasks) {
      if (t.status == TaskStatus.pending &&
          ((t.type == TaskType.flexible && t.deadline != null && now.isAfter(t.deadline!)) ||
              (t.type == TaskType.focus && now.isAfter(t.alarm.add(const Duration(minutes: 2)))))) {
        t.status = TaskStatus.failed;
        changed = true;
      }
    }
    if (changed) {
      save();
      if (mounted) setState(() {});
    }
  }

  // Verifica se há conflito SOMENTE entre tarefas de Foco
  bool hasConflict(Task targetTask, List<Task> dailyTasks) {
    if (targetTask.type == TaskType.flexible) return false;
    for (final other in dailyTasks) {
      if (other.id == targetTask.id || other.type == TaskType.flexible) continue;
      if (targetTask.start.isBefore(other.end) && targetTask.end.isAfter(other.start)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final dailyTasks = today;
    final focusTasks = dailyTasks.where((t) => t.type == TaskType.focus).toList();
    
    // Algoritmo de posicionamento para evitar sobreposição visual (Colunas)
    Map<String, int> colOffset = {};
    Map<String, int> colSpan = {};
    List<List<Task>> clusters = [];
    List<Task> currentCluster = [];
    DateTime? clusterEnd;

    for (var t in focusTasks) {
      if (currentCluster.isEmpty) {
        currentCluster.add(t);
        clusterEnd = t.end;
      } else {
        if (t.start.isBefore(clusterEnd!)) {
          currentCluster.add(t);
          if (t.end.isAfter(clusterEnd)) clusterEnd = t.end;
        } else {
          clusters.add(List.from(currentCluster));
          currentCluster = [t];
          clusterEnd = t.end;
        }
      }
    }
    if (currentCluster.isNotEmpty) clusters.add(currentCluster);

    for (var cluster in clusters) {
      List<List<Task>> cols = [];
      for (var t in cluster) {
        bool placed = false;
        for (int i = 0; i < cols.length; i++) {
          if (cols[i].last.end.compareTo(t.start) <= 0) {
            cols[i].add(t);
            colOffset[t.id] = i;
            placed = true;
            break;
          }
        }
        if (!placed) {
          cols.add([t]);
          colOffset[t.id] = cols.length - 1;
        }
      }
      for (var t in cluster) {
        colSpan[t.id] = cols.length;
      }
    }

    // Área útil da tela para calcular as larguras
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - 76; // Desconta espaço das horas e margem

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEE, d MMM', 'pt_BR').format(day)),
        actions: [
          IconButton(
            onPressed: () => setState(() => day = day.subtract(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(
            onPressed: () => setState(() => day = DateUtils.dateOnly(DateTime.now())),
            child: const Text('Hoje'),
          ),
          IconButton(
            onPressed: () => setState(() => day = day.add(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: Column(
        children: [
          if (blocked)
            Material(
              color: Colors.red,
              child: InkWell(
                onTap: () => resolve(tasks.firstWhere((x) => x.failed)),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Resolva suas pendências antes de planejar coisas novas.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: 24 * 76,
                child: Stack(
                  children: [
                    // Fundo: Linhas de horas
                    for (int i = 0; i < 24; i++)
                      Positioned(
                        top: i * 76,
                        left: 0,
                        right: 0,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: Text('${i.toString().padLeft(2, '0')}:00', textAlign: TextAlign.right),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(child: Divider(color: Colors.white12)),
                          ],
                        ),
                      ),
                    
                    // Linha do tempo atual
                    if (DateUtils.isSameDay(day, now))
                      Positioned(
                        top: (now.hour + now.minute / 60) * 76,
                        left: 0,
                        right: 0,
                        child: Container(height: 2, color: Colors.red),
                      ),
                    
                    // Renderização das Tarefas
                    ...dailyTasks.map((t) {
                      final top = (t.start.hour + t.start.minute / 60) * 76.0;
                      final height = (t.end.difference(t.start).inMinutes / 60 * 76).clamp(40.0, 1000.0);
                      
                      // Cálculo visual
                      final isFlexible = t.type == TaskType.flexible;
                      final inConflict = hasConflict(t, dailyTasks);
                      
                      // Posições baseadas no cluster (se for foco)
                      double leftPos = 64;
                      double itemWidth = availableWidth;
                      
                      if (!isFlexible) {
                        final span = colSpan[t.id] ?? 1;
                        final offset = colOffset[t.id] ?? 0;
                        itemWidth = availableWidth / span;
                        leftPos = 64 + (offset * itemWidth);
                      }

                      return Positioned(
                        top: top,
                        left: leftPos,
                        width: itemWidth,
                        height: height,
                        child: GestureDetector(
                          onTap: () => t.failed ? resolve(t) : actions(t),
                          child: Container(
                            margin: const EdgeInsets.only(right: 2, bottom: 2), // Espaçamento entre as colunas
                            decoration: BoxDecoration(
                              color: t.failed
                                  ? Colors.red.withValues(alpha: .25)
                                  : Color(t.color).withValues(alpha: isFlexible ? .15 : .85),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: t.failed || inConflict ? Colors.red : Color(t.color).withValues(alpha: isFlexible ? 0.5 : 1),
                                width: t.failed || inConflict ? 2 : 1,
                              ),
                              boxShadow: isFlexible ? [] : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(2, 2),
                                )
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                children: [
                                  if (inConflict)
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: HatchPainter(color: Colors.red.withValues(alpha: 0.5)),
                                      ),
                                    ),
                                  Positioned.fill(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${t.failed ? '⚠ ' : ''}${t.title}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Flexible(
                                            child: Text(
                                              '${DateFormat('HH:mm').format(t.start)} - ${DateFormat('HH:mm').format(t.end)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.white.withValues(alpha: 0.75),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
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
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: blocked ? null : () => showTaskForm(),
        child: Icon(blocked ? Icons.lock : Icons.add),
      ),
    );
  }

  // Refatorado: Serve para Adicionar e Editar, além de fixar o teclado e as cores
  Future<void> showTaskForm({Task? taskToEdit}) async {
    final title = TextEditingController(text: taskToEdit?.title ?? '');
    TaskType type = taskToEdit?.type ?? TaskType.focus;
    TimeOfDay startTime = taskToEdit != null ? TimeOfDay.fromDateTime(taskToEdit.start) : TimeOfDay.now();
    TimeOfDay endTime = taskToEdit?.deadline != null
        ? TimeOfDay.fromDateTime(taskToEdit!.deadline!)
        : TimeOfDay(hour: (startTime.hour + 1) % 24, minute: startTime.minute);
    
    int mins = taskToEdit?.minutes ?? 30;
    int selectedColor = taskToEdit?.color ?? taskColors[0].value;
    String? errorMessage;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) => StatefulBuilder(
        builder: (ctx, set) {
          void validateTimes() {
            final startTotal = startTime.hour * 60 + startTime.minute;
            final endTotal = endTime.hour * 60 + endTime.minute;
            if (type == TaskType.flexible && endTotal <= startTotal) {
              errorMessage = "O horário final deve ser maior que o inicial.";
            } else {
              errorMessage = null;
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 18,
              top: 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: taskToEdit == null,
                  decoration: const InputDecoration(hintText: 'O que precisa acontecer?'),
                ),
                const SizedBox(height: 16),
                
                // SegmentedButton substitui o Dropdown (Resolve o bug do teclado)
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<TaskType>(
                    segments: const [
                      ButtonSegment(value: TaskType.focus, label: Text('Foco')),
                      ButtonSegment(value: TaskType.flexible, label: Text('Janela Flexível')),
                    ],
                    selected: {type},
                    onSelectionChanged: (newSelection) {
                      set(() {
                        type = newSelection.first;
                        validateTimes();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                
                if (type == TaskType.focus)
                  ListTile(
                    title: Text('Início: ${startTime.format(ctx)}'),
                    onTap: () async {
                      final x = await showTimePicker(context: ctx, initialTime: startTime);
                      if (x != null) set(() => startTime = x);
                    },
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          title: Text('Início:\n${startTime.format(ctx)}', textAlign: TextAlign.center),
                          onTap: () async {
                            final x = await showTimePicker(context: ctx, initialTime: startTime);
                            if (x != null) {
                              set(() {
                                startTime = x;
                                validateTimes();
                              });
                            }
                          },
                        ),
                      ),
                      const Icon(Icons.arrow_forward_outlined, color: Colors.grey),
                      Expanded(
                        child: ListTile(
                          title: Text('Fim:\n${endTime.format(ctx)}', textAlign: TextAlign.center),
                          onTap: () async {
                            final x = await showTimePicker(context: ctx, initialTime: endTime);
                            if (x != null) {
                              set(() {
                                endTime = x;
                                validateTimes();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),

                // Slider corrigido: 15 a 120 min de 5 em 5 minutos = 21 divisões
                if (type == TaskType.focus)
                  Slider(
                    value: mins.toDouble(),
                    min: 15,
                    max: 120,
                    divisions: 21,
                    label: '$mins min',
                    onChanged: (v) => set(() => mins = v.round()),
                  ),

                // Seletor das 7 cores
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: taskColors.map((c) {
                      final isSelected = selectedColor == c.value;
                      return GestureDetector(
                        onTap: () => set(() => selectedColor = c.value),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                            boxShadow: isSelected ? [BoxShadow(color: c, blurRadius: 8)] : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),

                if (errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Text(errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),

                FilledButton(
                  onPressed: errorMessage != null ? null : () => Navigator.pop(ctx, true),
                  child: Text(taskToEdit == null ? 'Salvar Tarefa' : 'Atualizar Tarefa'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (ok != true || title.text.trim().isEmpty) return;

    final s = DateTime(day.year, day.month, day.day, startTime.hour, startTime.minute);
    DateTime? taskDeadline;
    if (type == TaskType.flexible) {
      taskDeadline = DateTime(day.year, day.month, day.day, endTime.hour, endTime.minute);
    }

    if (taskToEdit == null) {
      tasks.add(
        Task(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: title.text.trim(),
          type: type,
          start: s,
          color: selectedColor,
          minutes: mins,
          deadline: taskDeadline,
        ),
      );
    } else {
      setState(() {
        taskToEdit.title = title.text.trim();
        taskToEdit.type = type;
        taskToEdit.start = s;
        taskToEdit.color = selectedColor;
        taskToEdit.minutes = mins;
        taskToEdit.deadline = taskDeadline;
      });
    }

    await save();
    if (mounted) setState(() {});
  }

  void actions(Task t) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(t.title, style: const TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.check),
              title: const Text('Concluir'),
              onTap: () {
                setState(() => t.status = TaskStatus.done);
                save();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar Tarefa'),
              onTap: () {
                Navigator.pop(ctx);
                showTaskForm(taskToEdit: t);
              },
            ),
            if (t.snoozes < 3 && t.type == TaskType.focus)
              ListTile(
                leading: const Icon(Icons.snooze),
                title: Text('Adiar ${[10, 5, 2][t.snoozes]} min'),
                onTap: () {
                  setState(() {
                    t.snoozedUntil = DateTime.now().add(Duration(minutes: [10, 5, 2][t.snoozes]));
                    t.snoozes++;
                  });
                  save();
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Excluir manualmente'),
              onTap: () {
                setState(() => tasks.remove(t));
                save();
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  void resolve(Task t) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Falha: ${t.title}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Reagendar para hoje'),
              onTap: () {
                setState(() {
                  t.start = DateTime.now();
                  if (t.type == TaskType.flexible && t.deadline != null) {
                    final dur = t.deadline!.difference(t.start);
                    t.deadline = DateTime.now().add(dur);
                  }
                  t.status = TaskStatus.pending;
                  t.snoozes = 0;
                });
                save();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Reagendar para amanhã'),
              onTap: () {
                setState(() {
                  t.start = DateTime.now().add(const Duration(days: 1));
                  if (t.type == TaskType.flexible && t.deadline != null) {
                    final dur = t.deadline!.difference(t.start);
                    t.deadline = DateTime.now().add(const Duration(days: 1)).add(dur);
                  }
                  t.status = TaskStatus.pending;
                  t.snoozes = 0;
                });
                save();
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Excluir e assumir desistência'),
              onTap: () {
                setState(() => tasks.remove(t));
                save();
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}
