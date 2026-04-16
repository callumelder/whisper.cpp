local M = {}

local state = {
  menubar = nil,
  recordTask = nil,
  transcribeTask = nil,
  recordFile = nil,
  stopFile = nil,
  fnWatcher = nil,
  fnIsDown = false,
  shouldTranscribe = false,
  lastText = nil,
}

local defaults = {
  repo = "/Users/cal/dev/whisper.cpp",
  python = "/Users/cal/dev/whisper.cpp/.venv-coreml/bin/python3.11",
  shell = "/bin/zsh",
  threads = 8,
  tempDir = os.getenv("HOME") .. "/Library/Caches/whisper-dictation",
  model = "/Users/cal/dev/whisper.cpp/models/ggml-small.en.bin",
  vadModel = "/Users/cal/dev/whisper.cpp/models/ggml-silero-v6.2.0.bin",
  language = "en",
}

local config = {}

local function mergeConfig(overrides)
  config = {}
  for key, value in pairs(defaults) do
    config[key] = value
  end

  if overrides then
    for key, value in pairs(overrides) do
      config[key] = value
    end
  end

  config.recordScript = config.repo .. "/tools/macos-dictation/record-mic.py"
  config.transcribeScript = config.repo .. "/tools/macos-dictation/transcribe-file.sh"

  if not (overrides and overrides.model) then
    config.model = config.repo .. "/models/ggml-small.en.bin"
  end

  if not (overrides and overrides.vadModel) then
    config.vadModel = config.repo .. "/models/ggml-silero-v6.2.0.bin"
  end
end

local function cleanText(text)
  if not text then
    return ""
  end

  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")

  return text
end

local function shellQuote(value)
  return string.format("%q", value)
end

local function ensureTempDir()
  hs.fs.mkdir(config.tempDir)
end

local function setStatus(label)
  if not state.menubar then
    state.menubar = hs.menubar.new()
  end

  state.menubar:setTitle(label)
  state.menubar:setTooltip("Whisper dictation")
end

local function refreshMenu()
  if not state.menubar then
    return
  end

  state.menubar:setMenu({
    {
      title = "Mode: Hold fn to dictate",
      disabled = true,
    },
    {
      title = "Input: macOS default microphone",
      disabled = true,
    },
    {
      title = "Model: ggml-small.en.bin",
      disabled = true,
    },
    {
      title = "Threads: " .. tostring(config.threads),
      disabled = true,
    },
    {
      title = "Reload Config",
      fn = hs.reload,
    },
  })
end

local function notify(text)
  hs.alert.closeAll()
  hs.alert.show(text, 1.2)
end

local function restoreClipboard(previous)
  if previous and previous ~= "" then
    hs.pasteboard.setContents(previous)
  else
    hs.pasteboard.clearContents()
  end
end

local function pasteText(text)
  local previous = hs.pasteboard.getContents()

  hs.pasteboard.setContents(text)

  hs.timer.doAfter(0.05, function()
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    hs.timer.doAfter(0.2, function()
      restoreClipboard(previous)
    end)
  end)
end

local function finishTranscription(exitCode, stdOut, stdErr)
  local text = cleanText(stdOut)
  state.transcribeTask = nil
  setStatus("V2T")
  refreshMenu()

  if exitCode ~= 0 then
    notify("Dictation failed")
    if stdErr and stdErr ~= "" then
      print(stdErr)
    end
    return
  end

  if text == "" then
    notify("No speech detected")
    return
  end

  state.lastText = text
  pasteText(text)
  notify("Dictation pasted")
end

local function transcribeFile(audioFile)
  setStatus("V2T...")
  refreshMenu()

  local command = table.concat({
    "WHISPER_DICTATION_THREADS=" .. shellQuote(tostring(config.threads)),
    "WHISPER_DICTATION_MODEL=" .. shellQuote(config.model),
    "WHISPER_DICTATION_VAD_MODEL=" .. shellQuote(config.vadModel),
    "WHISPER_DICTATION_LANGUAGE=" .. shellQuote(config.language),
    shellQuote(config.transcribeScript),
    shellQuote(audioFile),
  }, " ")

  state.transcribeTask = hs.task.new(
    config.shell,
    function(exitCode, stdOut, stdErr)
      finishTranscription(exitCode, stdOut, stdErr)
      if audioFile then
        os.remove(audioFile)
      end
    end,
    { "-lc", command }
  )

  if not state.transcribeTask:start() then
    state.transcribeTask = nil
    setStatus("V2T")
    refreshMenu()
    notify("Could not start transcription")
  end
end

local function finishRecording(exitCode, _, stdErr)
  local audioFile = state.recordFile
  local shouldTranscribe = state.shouldTranscribe

  state.recordTask = nil
  state.recordFile = nil
  state.stopFile = nil
  state.shouldTranscribe = false

  if exitCode ~= 0 and not shouldTranscribe then
    setStatus("V2T")
    refreshMenu()
    notify("Recording failed")
    if stdErr and stdErr ~= "" then
      print(stdErr)
    end
    if audioFile then
      os.remove(audioFile)
    end
    return
  end

  if shouldTranscribe and audioFile then
    transcribeFile(audioFile)
  else
    setStatus("V2T")
    refreshMenu()
  end
end

local function startRecording()
  if state.transcribeTask then
    notify("Still transcribing")
    return
  end

  if state.recordTask then
    return
  end

  ensureTempDir()

  local timestamp = os.date("%Y%m%d-%H%M%S")
  local audioFile = string.format("%s/dictation-%s.wav", config.tempDir, timestamp)
  local stopFile = string.format("%s/dictation-%s.stop", config.tempDir, timestamp)

  state.recordFile = audioFile
  state.stopFile = stopFile
  state.shouldTranscribe = false
  state.recordTask = hs.task.new(
    config.python,
    finishRecording,
    {
      config.recordScript,
      "--output", audioFile,
      "--stop-file", stopFile,
    }
  )

  if not state.recordTask:start() then
    state.recordTask = nil
    state.recordFile = nil
    state.stopFile = nil
    notify("Could not start recording")
    return
  end

  setStatus("REC")
  refreshMenu()
  notify("Recording")
end

local function stopRecording()
  if not state.recordTask then
    return
  end

  state.shouldTranscribe = true
  setStatus("V2T...")
  refreshMenu()

  if state.stopFile then
    local handle = io.open(state.stopFile, "w")
    if handle then
      handle:write("stop\n")
      handle:close()
    end
  end

  notify("Transcribing")
end

local function fnOnly(flags)
  return flags.fn
    and not flags.cmd
    and not flags.alt
    and not flags.shift
    and not flags.ctrl
    and not flags.capslock
end

local function handleFlagsChanged(event)
  local flags = event:getFlags()
  local fnDown = fnOnly(flags)

  if fnDown and not state.fnIsDown then
    state.fnIsDown = true
    startRecording()
    return true
  end

  if not fnDown and state.fnIsDown then
    state.fnIsDown = false
    stopRecording()
    return true
  end

  return false
end

function M.setup(overrides)
  mergeConfig(overrides)
  ensureTempDir()
  setStatus("V2T")
  refreshMenu()

  if state.fnWatcher then
    state.fnWatcher:stop()
  end

  state.fnWatcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, handleFlagsChanged)
  state.fnWatcher:start()

  _G.whisper_dictation = {
    start = startRecording,
    stop = stopRecording,
    status = function()
      local pid = nil
      local running = false
      if state.recordTask then
        pid = state.recordTask:pid()
        running = state.recordTask:isRunning()
      end

      return {
        recording = state.recordTask ~= nil,
        recordTaskRunning = running,
        pid = pid,
        transcribing = state.transcribeTask ~= nil,
        lastText = state.lastText,
      }
    end,
  }

  print(string.format(
    "whisper_dictation loaded | repo=%s | mode=hold-fn",
    config.repo
  ))
end

return M
