# Termina

Il terminale di Linux, Windows e macOS, senza memorizzare opzioni.
Scrivi un comando (`tar`, `ffmpeg`, `git log`…) o descrivi cosa vuoi fare
("trova i file più grandi"): Termina legge la documentazione del programma e,
con [genui](https://pub.dev/packages/genui), genera un'interfaccia grafica
su misura. Il comando risultante è sempre visibile, si aggiorna mentre compili
il form e si esegue con un clic.

## Come funziona

1. **Documentazione**: se la prima parola è un eseguibile installato, Termina
   ne raccoglie `--help` / `-h` / `man` (o `Get-Help` su Windows).
2. **Generazione**: richiesta e documentazione vanno all'LLM, che risponde con
   messaggi A2UI (`createSurface`, `updateDataModel`, `updateComponents`).
   `genui` li interpreta e disegna il form.
3. **Comando live**: il componente custom `CommandRunner` ha un template legato
   al data model, ad esempio `tar {{/gzip?-z}} -cf {{/archive}} {{/files}}`.
   I valori vengono quotati per la shell in automatico.
4. **Esecuzione**: il comando gira nella shell di sistema (`$SHELL -c`,
   oppure PowerShell su Windows) dentro la cartella di lavoro scelta, con
   l'output in streaming. I comandi segnati come `dangerous` chiedono conferma.
5. **Modifiche**: dopo la generazione puoi chiedere modifiche ("aggiungi
   l'opzione per escludere i file .log") e l'LLM aggiorna la stessa interfaccia.

### Sintassi dei template

| Placeholder        | Risultato                                                  |
| ------------------ | ---------------------------------------------------------- |
| `{{/path}}`        | valore quotato; vuoto/`false` → niente; liste → più parole |
| `{{/path?testo}}`  | `testo` se il valore è "vero"; `%s` = valore quotato       |
| `{{!/path?testo}}` | `testo` se il valore è "falso"                             |

## Struttura

```
lib/
  main.dart
  src/
    catalog/   catalogo genui: widget base + CommandRunner + PathPicker
    command/   motore dei template dei comandi (puro Dart)
    genui/     TerminaSession: Conversation, transport, storico, prompt
    llm/       client in streaming: Claude, Gemini e OpenAI-compatibile
    settings/  impostazioni persistenti (shared_preferences)
    shell/     rilevamento shell/OS, lettura help, esecuzione processi
    ui/        pagina principale, console di output, impostazioni
```

## Configurazione del modello

- **Claude** (predefinito, `claude-opus-5-5`): inserisci la API key nelle
  impostazioni, oppure esporta `ANTHROPIC_API_KEY`. Puoi abbassare l'effort a
  `low` per avere risposte più rapide.
- **Gemini** (`gemini-3.8-flash`): crea una API key su
  [Google AI Studio](https://aistudio.google.com/apikey) e inseriscila nelle
  impostazioni, oppure esporta `GEMINI_API_KEY` (o `GOOGLE_API_KEY`).
  Il livello di ragionamento (`low`/`medium`/`high`) diventa `thinkingLevel`.
- **OpenAI-compatibile**: qualsiasi endpoint `/chat/completions` (Ollama,
  LM Studio…), ad esempio `http://localhost:11434/v1`.

Le chiavi sono salvate in chiaro nelle preferenze locali dell'app.

## Avvio

```bash
flutter pub get
flutter run -d linux     # oppure: -d macos, -d windows
flutter test
```

**Linux**: `genui` dipende da `audioplayers`, che richiede GStreamer:

```bash
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

**macOS**: l'App Sandbox è disattivata in `macos/Runner/*.entitlements`,
perché altrimenti Termina non potrebbe lanciare comandi arbitrari.

## Limiti

I comandi girano senza TTY: i programmi a schermo intero (vim, top, less) non
sono supportati. Termina propone invece alternative non interattive. Puoi
comunque inviare righe di input a un processo in esecuzione dalla console.
