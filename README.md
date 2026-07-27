# Foco TDAH

MVP Flutter offline da agenda anti-paralisia executiva.

## O que já funciona
- Persistência local das tarefas em JSON via SharedPreferences
- Tarefa de Foco e Janela Flexível
- Agenda diária vertical com linha do tempo real
- Detecção visual de conflito entre tarefas de Foco
- Escada de adiamentos: 10, 5 e 2 minutos
- Falha automática e Tag da Vergonha
- Bloqueio de novas tarefas enquanto houver falha
- Reagendar para hoje/amanhã ou excluir manualmente

## Como gerar o APK no Codemagic
1. Faça upload deste conteúdo para o repositório GitHub.
2. No Codemagic, conecte `christyanengeco-cyber/taskapp`.
3. Selecione Flutter, branch `main`, workflow Android.
4. Rode o build. O arquivo será `build/app/outputs/flutter-apk/app-release.apk`.

O arquivo `codemagic.yaml` automatiza a preparação Android caso o diretório `android/` ainda não exista.

## Próxima fase
Alarmes nativos full-screen, widget Android e overlay exigem configuração Android específica e devem ser validados no celular antes de considerar o app pronto para uso diário.
