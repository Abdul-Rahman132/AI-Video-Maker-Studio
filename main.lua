require "import"
import "android.app.*"
import "android.os.*"
import "android.widget.*"
import "android.view.*"
import "android.view.inputmethod.EditorInfo"
import "android.view.inputmethod.InputMethodManager"
import "android.text.TextWatcher"
import "android.text.InputType"
import "android.graphics.*"
import "android.graphics.drawable.GradientDrawable"
import "android.media.*"
import "android.content.*"
import "android.net.Uri"
import "android.provider.MediaStore"
import "java.io.*"
import "java.util.ArrayList"
import "java.net.URLEncoder"

local TOOL_TITLE = "AI Video Maker Studio"
local DEV_NAME = "Developer: Abdul Rehman"
local WHATSAPP_NO = "+92 3124255300"
local WHATSAPP_DIGITS = "923124255300"

local CACHE_DIR = activity.getCacheDir().getAbsolutePath() .. "/ai_video_maker_cache"
local DOWNLOAD_DIR = "/storage/emulated/0/Download/AI_Video_Maker_Studio"
File(CACHE_DIR).mkdirs()

local currentMode = "text" -- "text" or "audio"
local selectedAudioPath = nil
local selectedAudioName = nil
local currentVideoPath = nil
local currentVideoTitle = "AI_Video_" .. os.date("%Y%m%d_%H%M%S")
local welcomePlayer = nil
local previewPlayer = nil
local isGenerating = false
local isHiddenInBackground = false
local statusTicker = nil
local progressFile = CACHE_DIR .. "/progress_status.txt"

local FORMATS = {
  {label = "YouTube Landscape (1280x720)", w = 1280, h = 720},
  {label = "Shorts and Reels (720x1280)", w = 720, h = 1280},
  {label = "Square Video (720x720)", w = 720, h = 720}
}

local VISUAL_STYLES = {
  {label = "Cinematic Realistic", prompt = "cinematic realistic live action movie scene, dramatic lighting, ultra detailed, 8k film still"},
  {label = "Dark Thriller Mystery", prompt = "cinematic noir thriller movie scene, moody shadows, dramatic lighting, realistic characters, 8k"},
  {label = "3D Animation Style", prompt = "3d pixar disney animation style, expressive characters, vibrant cinematic lighting, ultra detailed"},
  {label = "Spiritual Scenic Art", prompt = "serene spiritual islamic art atmosphere, golden hour light, majestic scenery, peaceful, 8k"},
  {label = "Documentary Historical", prompt = "historical documentary movie scene, authentic realistic details, cinematic natural lighting, 8k"},
  {label = "Anime Illustration", prompt = "high quality anime cinematic movie frame, vivid colors, dramatic storytelling art"}
}

local VOICES = {
  {label = "Auto (Urdu or English)", id = "auto"},
  {label = "Urdu Clear Voice", id = "ur"},
  {label = "English Studio Male (Matthew)", id = "Matthew"},
  {label = "English British Male (Brian)", id = "Brian"},
  {label = "English Female (Joanna)", id = "Joanna"}
}

local TRANSITIONS = {
  {label = "Smooth Crossfade", id = "crossfade"},
  {label = "Fade Through Black", id = "fadeblack"},
  {label = "Instant Cut", id = "cut"}
}

local SUB_MODES = {
  {label = "Subtitles: ON", enabled = true},
  {label = "Subtitles: OFF", enabled = false}
}

local selectedFormatIdx = 1
local selectedStyleIdx = 1
local selectedVoiceIdx = 1
local selectedTransIdx = 1
local selectedSubIdx = 1

local density = activity.getResources().getDisplayMetrics().density
local function dp(val)
  return math.floor(val * density)
end

local function haptic(ms)
  pcall(function()
    local vib = activity.getSystemService(Context.VIBRATOR_SERVICE)
    if vib and vib.hasVibrator() then
      if Build.VERSION.SDK_INT >= 26 then
        vib.vibrate(VibrationEffect.createOneShot(ms or 35, VibrationEffect.DEFAULT_AMPLITUDE))
      else
        vib.vibrate(ms or 35)
      end
    end
  end)
end

local function makeCardBg(fillHex, radiusDp, strokeHex, strokeDp)
  local gd = GradientDrawable()
  gd.setColor(Color.parseColor(fillHex))
  if radiusDp and radiusDp > 0 then
    gd.setCornerRadius(dp(radiusDp))
  end
  if strokeHex then
    gd.setStroke(dp(strokeDp or 1.4), Color.parseColor(strokeHex))
  end
  return gd
end

local function makeGradBg(startHex, endHex, radiusDp, strokeHex, strokeDp)
  local gd = GradientDrawable(
    GradientDrawable.Orientation.TL_BR,
    int{Color.parseColor(startHex), Color.parseColor(endHex)}
  )
  if radiusDp and radiusDp > 0 then
    gd.setCornerRadius(dp(radiusDp))
  end
  if strokeHex then
    gd.setStroke(dp(strokeDp or 1.5), Color.parseColor(strokeHex))
  end
  return gd
end

local function setHeading(tv)
  tv.setFocusable(true)
  tv.setFocusableInTouchMode(false)
  if Build.VERSION.SDK_INT >= 28 then
    pcall(function() tv.setAccessibilityHeading(true) end)
  end
end

local function showStyledDialog(view)
  local dlg = AlertDialog.Builder(activity).setView(view).create()
  pcall(function()
    if dlg.getWindow() then
      dlg.getWindow().setBackgroundDrawableResource(android.R.color.transparent)
    end
  end)
  dlg.show()
  return dlg
end

local function stopPreviewPlayer()
  if previewPlayer then
    pcall(function() previewPlayer.stop() end)
    pcall(function() previewPlayer.release() end)
    previewPlayer = nil
  end
end

local function sendReadyNotification(titleText, bodyText)
  pcall(function()
    local nm = activity.getSystemService(Context.NOTIFICATION_SERVICE)
    local chanId = "ai_video_maker_ready"
    if Build.VERSION.SDK_INT >= 26 then
      local ch = NotificationChannel(chanId, "Video Generation Alerts", NotificationManager.IMPORTANCE_HIGH)
      ch.setDescription("Alerts when your video finishes rendering")
      nm.createNotificationChannel(ch)
    end
    local openIntent = Intent(activity, activity.getClass())
    openIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
    local flags = PendingIntent.FLAG_UPDATE_CURRENT
    if Build.VERSION.SDK_INT >= 23 then
      flags = flags | PendingIntent.FLAG_IMMUTABLE
    end
    local pi = PendingIntent.getActivity(activity, 902, openIntent, flags)
    local builder = (Build.VERSION.SDK_INT >= 26)
      and Notification.Builder(activity, chanId)
      or  Notification.Builder(activity)
    builder.setContentTitle(titleText)
      .setContentText(bodyText)
      .setSmallIcon(android.R.drawable.ic_media_play)
      .setAutoCancel(true)
      .setContentIntent(pi)
    nm.notify(902, builder.build())
  end)
end

local function bringAppToFront()
  pcall(function()
    local am = activity.getSystemService(Context.ACTIVITY_SERVICE)
    if am and activity.getTaskId then
      am.moveTaskToFront(activity.getTaskId(), 0)
    end
  end)
  pcall(function()
    local intent = Intent(activity, activity.getClass())
    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP)
    activity.startActivity(intent)
  end)
end

local function hideToHomeScreen()
  pcall(function()
    local home = Intent(Intent.ACTION_MAIN)
    home.addCategory(Intent.CATEGORY_HOME)
    home.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    activity.startActivity(home)
  end)
  pcall(function() activity.moveTaskToBack(true) end)
end

local function playAudioFile(path, onDone)
  if not path or not File(path).exists() then
    if onDone then onDone() end
    return
  end
  pcall(function()
    if welcomePlayer then
      pcall(function() welcomePlayer.stop() end)
      pcall(function() welcomePlayer.release() end)
      welcomePlayer = nil
    end
    welcomePlayer = MediaPlayer()
    if Build.VERSION.SDK_INT >= 21 then
      local attrs = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
      welcomePlayer.setAudioAttributes(attrs)
    else
      welcomePlayer.setAudioStreamType(AudioManager.STREAM_MUSIC)
    end
    welcomePlayer.setDataSource(path)
    welcomePlayer.setVolume(1.0, 1.0)
    welcomePlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener{
      onCompletion = function(mp)
        pcall(function() mp.release() end)
        if welcomePlayer == mp then welcomePlayer = nil end
        if onDone then onDone() end
      end
    })
    welcomePlayer.prepare()
    welcomePlayer.start()
  end)
end

-- Studio chime + Clear Studio Announcer Welcome
local function playWelcomeIntro(cachePath)
  task(function(outDir)
    require "import"
    import "java.io.*"
    import "java.net.*"

    local chimePath = outDir .. "/video_maker_chime_v2.wav"
    local chk = io.open(chimePath, "rb")
    local hasChime = false
    if chk then
      local sz = chk:seek("end")
      chk:close()
      if sz and sz > 8000 then hasChime = true end
    end

    if not hasChime then
      local sr = 16000
      local totalSec = 0.78
      local totalSamples = math.floor(sr * totalSec)
      local notes = {
        {f = 261.63, s = 0.00, a = 0.28, d = 4.2},
        {f = 329.63, s = 0.07, a = 0.25, d = 4.4},
        {f = 392.00, s = 0.14, a = 0.25, d = 4.6},
        {f = 523.25, s = 0.21, a = 0.24, d = 4.8},
        {f = 659.25, s = 0.28, a = 0.22, d = 5.0}
      }
      local function le16(v)
        v = math.floor(v)
        if v < 0 then v = v + 65536 end
        return string.char(v % 256, math.floor(v / 256) % 256)
      end
      local function le32(v)
        v = math.floor(v)
        if v < 0 then v = v + 4294967296 end
        return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
      end
      local dataBytes = totalSamples * 2
      local header = "RIFF" .. le32(36 + dataBytes) .. "WAVEfmt "
        .. le32(16) .. le16(1) .. le16(1)
        .. le32(sr) .. le32(sr * 2) .. le16(2) .. le16(16)
        .. "data" .. le32(dataBytes)
      local chunks = {header}
      local buf = {}
      local bi = 0
      local sin, exp, floor, char = math.sin, math.exp, math.floor, string.char
      local twoPi = 6.28318530718
      for i = 0, totalSamples - 1 do
        local t = i / sr
        local mix = 0.0
        for k = 1, 5 do
          local n = notes[k]
          if t >= n.s then
            local dt = t - n.s
            local env = (dt < 0.01 and (dt / 0.01) or 1.0) * exp(-n.d * dt)
            local ph = twoPi * n.f * dt
            mix = mix + n.a * env * (sin(ph) + 0.22 * sin(ph * 2.0))
          end
        end
        if t > 0.60 then
          local fade = (totalSec - t) / (totalSec - 0.60)
          if fade < 0 then fade = 0 end
          mix = mix * fade
        end
        if mix > 0.92 then mix = 0.92 elseif mix < -0.92 then mix = -0.92 end
        local pcm = floor(mix * 31000)
        if pcm < 0 then pcm = pcm + 65536 end
        bi = bi + 1
        buf[bi] = char(pcm % 256, floor(pcm / 256) % 256)
        if bi >= 2048 then
          chunks[#chunks + 1] = table.concat(buf)
          buf = {}
          bi = 0
        end
      end
      if bi > 0 then chunks[#chunks + 1] = table.concat(buf) end
      local f = io.open(chimePath, "wb")
      if f then
        f:write(table.concat(chunks))
        f:close()
      end
    end

    local voicePath = outDir .. "/video_maker_welcome_v2.mp3"
    local vFile = File(voicePath)
    local hasVoice = vFile.exists() and vFile.length() > 4000

    local function dlAudio(urlStr, dest)
      local ok = pcall(function()
        local conn = URL(urlStr).openConnection()
        conn.setConnectTimeout(12000)
        conn.setReadTimeout(20000)
        conn.setInstanceFollowRedirects(true)
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13)")
        local code = conn.getResponseCode()
        local ctype = tostring(conn.getContentType() or "")
        if code == 200 and (ctype:find("audio") or ctype:find("mpeg") or ctype:find("octet")) then
          local inp = BufferedInputStream(conn.getInputStream())
          local out = FileOutputStream(dest)
          local buf = byte[4096]
          local n = inp.read(buf)
          while n ~= -1 do
            out.write(buf, 0, n)
            n = inp.read(buf)
          end
          out.flush()
          out.close()
          inp.close()
        end
        conn.disconnect()
      end)
      return ok and File(dest).exists() and File(dest).length() > 4000
    end

    if not hasVoice then
      local msg = URLEncoder.encode("Welcome back to AI Video Maker Studio, developed by Abdul Rehman.", "UTF-8"):gsub("+", "%%20")
      hasVoice = dlAudio("https://api.streamelements.com/kappa/v2/speech?voice=Matthew&text=" .. msg, voicePath)
      if not hasVoice then
        hasVoice = dlAudio("https://api.streamelements.com/kappa/v2/speech?voice=Brian&text=" .. msg, voicePath)
      end
      if not hasVoice then
        hasVoice = dlAudio("https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en-US&q=" .. msg, voicePath)
      end
    end

    return chimePath, (hasVoice and voicePath or nil)
  end, cachePath, function(chimePath, voicePath)
    playAudioFile(chimePath, function()
      if voicePath then
        playAudioFile(voicePath, nil)
      end
    end)
  end)
end

-- ==========================================
-- IN-TOOL ACCESSIBLE AUDIO PICKER WINDOW (Deep Teal Theme + Live Search + Inline Play/Pause)
-- ==========================================
local function scanDeviceAudios()
  local list = {}
  local seen = {}
  pcall(function()
    local cr = activity.getContentResolver()
    local uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
    local proj = String{"_data", "_display_name", "duration"}
    local cursor = cr.query(uri, proj, nil, nil, "date_added DESC")
    if cursor then
      while cursor.moveToNext() do
        local p = cursor.getString(0)
        local n = cursor.getString(1)
        local dur = cursor.getLong(2)
        if p and File(p).exists() and File(p).length() > 2000 and not seen[p] then
          seen[p] = true
          if not n or n == "" then n = File(p).getName() end
          list[#list + 1] = {path = p, name = n, durMs = dur or 0}
        end
      end
      cursor.close()
    end
  end)

  if #list == 0 then
    local dirs = {
      "/storage/emulated/0/Download",
      "/storage/emulated/0/Music",
      "/storage/emulated/0/Recordings",
      "/storage/emulated/0/Audio"
    }
    local function scanDir(dPath, depth)
      if depth > 2 then return end
      local d = File(dPath)
      if not d.exists() or not d.isDirectory() then return end
      local files = d.listFiles()
      if not files then return end
      for i = 0, #files - 1 do
        local f = files[i]
        if f.isDirectory() then
          scanDir(f.getAbsolutePath(), depth + 1)
        else
          local nm = f.getName()
          local low = string.lower(nm)
          if (low:find("%.mp3$") or low:find("%.wav$") or low:find("%.m4a$") or low:find("%.aac$") or low:find("%.ogg$") or low:find("%.opus$")) and f.length() > 2000 then
            local fp = f.getAbsolutePath()
            if not seen[fp] then
              seen[fp] = true
              list[#list + 1] = {path = fp, name = nm, durMs = 0}
            end
          end
        end
      end
    end
    for _, dpPath in ipairs(dirs) do scanDir(dpPath, 0) end
  end
  return list
end

local function formatDur(ms)
  if not ms or ms <= 0 then return "" end
  local totalSec = math.floor(ms / 1000)
  local m = math.floor(totalSec / 60)
  local s = totalSec % 60
  return string.format(" (%02d:%02d)", m, s)
end

local function showInToolAudioPicker(onAudioPicked)
  stopPreviewPlayer()
  if welcomePlayer then
    pcall(function() welcomePlayer.stop() welcomePlayer.release() end)
    welcomePlayer = nil
  end

  local allAudios = scanDeviceAudios()

  local wrap = LinearLayout(activity)
  wrap.setOrientation(LinearLayout.VERTICAL)
  wrap.setPadding(dp(16), dp(16), dp(16), dp(16))
  wrap.setBackground(makeGradBg("#062925", "#041413", 22, "#14B8A6", 2.0))

  local topCard = LinearLayout(activity)
  topCard.setOrientation(LinearLayout.VERTICAL)
  topCard.setPadding(dp(14), dp(12), dp(14), dp(12))
  topCard.setBackground(makeGradBg("#0B3B35", "#072622", 14, "#2DD4BF", 1.3))

  local hTv = TextView(activity)
  hTv.setText("Select Audio File")
  hTv.setTextColor(Color.parseColor("#CCFBF1"))
  hTv.setTextSize(19)
  hTv.setTypeface(Typeface.DEFAULT_BOLD)
  setHeading(hTv)
  topCard.addView(hTv)

  local countTv = TextView(activity)
  countTv.setText("Total Audios on Device: " .. tostring(#allAudios))
  countTv.setTextColor(Color.parseColor("#FDE68A"))
  countTv.setTextSize(13)
  countTv.setTypeface(Typeface.DEFAULT_BOLD)
  countTv.setPadding(0, dp(4), 0, 0)
  countTv.setFocusable(true)
  topCard.addView(countTv)

  wrap.addView(topCard)

  -- Single Clean Live Search Box (No separate SEARCH button; Keyboard Enter = Search)
  local etSearch = EditText(activity)
  etSearch.setSingleLine(true)
  etSearch.setInputType(InputType.TYPE_CLASS_TEXT)
  etSearch.setImeOptions(EditorInfo.IME_ACTION_SEARCH)
  etSearch.setHint("Search audio...")
  etSearch.setHintTextColor(Color.parseColor("#94A3B8"))
  etSearch.setTextColor(Color.parseColor("#FFFFFF"))
  etSearch.setTextSize(14)
  etSearch.setPadding(dp(14), dp(11), dp(14), dp(11))
  etSearch.setBackground(makeCardBg("#041211", 12, "#2DD4BF", 1.3))
  etSearch.setContentDescription("Search audio")
  local lpSearch = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpSearch.topMargin = dp(10)
  lpSearch.bottomMargin = dp(10)
  wrap.addView(etSearch, lpSearch)

  local listSv = ScrollView(activity)
  local listBox = LinearLayout(activity)
  listBox.setOrientation(LinearLayout.VERTICAL)
  listSv.addView(listBox)
  wrap.addView(listSv, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(320)))

  local dlg = nil
  local activePlayBtn = nil
  local activePlayPath = nil

  local function hideKeyboard(view)
    pcall(function()
      local imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE)
      if imm and view then
        imm.hideSoftInputFromWindow(view.getWindowToken(), 0)
      end
    end)
  end

  local function showKeyboard(view)
    pcall(function()
      if view then
        view.requestFocus()
        local imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE)
        if imm then
          imm.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
        end
      end
    end)
  end

  local function renderList(queryStr)
    stopPreviewPlayer()
    activePlayBtn = nil
    activePlayPath = nil
    listBox.removeAllViews()

    local q = string.lower((queryStr or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    local matches = {}
    for _, item in ipairs(allAudios) do
      if q == "" or string.lower(item.name):find(q, 1, true) then
        matches[#matches + 1] = item
      end
    end

    if q == "" then
      countTv.setText("Total Audios on Device: " .. tostring(#allAudios))
    else
      countTv.setText("Showing " .. tostring(#matches) .. " of " .. tostring(#allAudios) .. " Audios")
    end

    if #matches == 0 then
      local emptyTv = TextView(activity)
      emptyTv.setText("No audio files found.")
      emptyTv.setTextColor(Color.parseColor("#CBD5E1"))
      emptyTv.setTextSize(14)
      emptyTv.setPadding(dp(8), dp(16), dp(8), dp(16))
      emptyTv.setFocusable(true)
      listBox.addView(emptyTv)
      return
    end

    local limit = math.min(#matches, 120)
    for i = 1, limit do
      local item = matches[i]
      local row = LinearLayout(activity)
      row.setOrientation(LinearLayout.HORIZONTAL)
      row.setGravity(Gravity.CENTER_VERTICAL)
      row.setPadding(dp(8), dp(6), dp(8), dp(6))
      row.setBackground(makeCardBg("#0A2220", 12, "#115E59", 1.1))
      local lpRow = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
      lpRow.bottomMargin = dp(8)

      local btnName = Button(activity)
      btnName.setText(item.name .. formatDur(item.durMs))
      btnName.setAllCaps(false)
      btnName.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL)
      btnName.setTextColor(Color.parseColor("#F0FDFA"))
      btnName.setTextSize(13)
      btnName.setPadding(dp(8), dp(8), dp(8), dp(8))
      btnName.setBackgroundColor(Color.TRANSPARENT)
      local lpNm = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1)
      btnName.setOnClickListener(View.OnClickListener{
        onClick = function()
          haptic(35)
          hideKeyboard(etSearch)
          stopPreviewPlayer()
          onAudioPicked(item.path, item.name)
          if dlg then dlg.dismiss() end
        end
      })
      row.addView(btnName, lpNm)

      local btnPrev = Button(activity)
      btnPrev.setText("PLAY")
      btnPrev.setAllCaps(false)
      btnPrev.setTextColor(Color.parseColor("#041413"))
      btnPrev.setTextSize(12)
      btnPrev.setTypeface(Typeface.DEFAULT_BOLD)
      btnPrev.setPadding(dp(12), dp(8), dp(12), dp(8))
      btnPrev.setBackground(makeGradBg("#F59E0B", "#D97706", 10, "#FDE68A", 1.1))
      local lpPv = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
      lpPv.leftMargin = dp(6)
      btnPrev.setOnClickListener(View.OnClickListener{
        onClick = function()
          haptic(35)
          if activePlayPath == item.path and previewPlayer then
            if previewPlayer.isPlaying() then
              pcall(function() previewPlayer.pause() end)
              btnPrev.setText("PLAY")
            else
              pcall(function() previewPlayer.start() end)
              btnPrev.setText("PAUSE")
            end
            return
          end
          if activePlayBtn then
            pcall(function() activePlayBtn.setText("PLAY") end)
          end
          stopPreviewPlayer()
          activePlayBtn = btnPrev
          activePlayPath = item.path
          pcall(function()
            previewPlayer = MediaPlayer()
            if Build.VERSION.SDK_INT >= 21 then
              local attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
              previewPlayer.setAudioAttributes(attrs)
            else
              previewPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC)
            end
            previewPlayer.setDataSource(item.path)
            previewPlayer.setOnCompletionListener(MediaPlayer.OnCompletionListener{
              onCompletion = function()
                if activePlayBtn then pcall(function() activePlayBtn.setText("PLAY") end) end
              end
            })
            previewPlayer.prepare()
            previewPlayer.start()
            btnPrev.setText("PAUSE")
          end)
        end
      })
      row.addView(btnPrev, lpPv)

      listBox.addView(row, lpRow)
    end
  end

  etSearch.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      showKeyboard(etSearch)
    end
  })

  etSearch.setOnEditorActionListener(TextView.OnEditorActionListener{
    onEditorAction = function(v, actionId, event)
      if actionId == EditorInfo.IME_ACTION_SEARCH or actionId == EditorInfo.IME_ACTION_DONE then
        haptic(35)
        renderList(etSearch.getText().toString())
        hideKeyboard(etSearch)
        return true
      end
      return false
    end
  })

  etSearch.addTextChangedListener(TextWatcher{
    beforeTextChanged = function(s, start, count, after) end,
    onTextChanged = function(s, start, before, count)
      renderList(tostring(s or ""))
    end,
    afterTextChanged = function(s) end
  })

  local btnClosePicker = Button(activity)
  btnClosePicker.setText("CLOSE")
  btnClosePicker.setAllCaps(false)
  btnClosePicker.setTextColor(Color.parseColor("#F8FAFC"))
  btnClosePicker.setTextSize(14)
  btnClosePicker.setTypeface(Typeface.DEFAULT_BOLD)
  btnClosePicker.setPadding(dp(12), dp(11), dp(12), dp(11))
  btnClosePicker.setBackground(makeCardBg("#27272A", 13, "#52525B", 1.2))
  local lpCP = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpCP.topMargin = dp(10)
  btnClosePicker.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      hideKeyboard(etSearch)
      stopPreviewPlayer()
      if dlg then dlg.dismiss() end
    end
  })
  wrap.addView(btnClosePicker, lpCP)

  renderList("")
  dlg = showStyledDialog(wrap)
  pcall(function()
    if dlg.getWindow() then
      dlg.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
    end
  end)
  dlg.setOnDismissListener(DialogInterface.OnDismissListener{
    onDismiss = function()
      stopPreviewPlayer()
    end
  })
end

-- ==========================================
-- MAIN STUDIO WINDOW (Rich Multi-Color Luxury Dark Theme)
-- ==========================================
local rootScroll = ScrollView(activity)
rootScroll.setBackgroundColor(Color.parseColor("#09090B"))
rootScroll.setFillViewport(true)

local mainBox = LinearLayout(activity)
mainBox.setOrientation(LinearLayout.VERTICAL)
mainBox.setPadding(dp(16), dp(18), dp(16), dp(26))
rootScroll.addView(mainBox)

local function addGap(parent, hDp)
  local v = View(activity)
  parent.addView(v, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(hDp)))
end

local function makeSectionCard(startHex, endHex, borderHex, strokeDp)
  local card = LinearLayout(activity)
  card.setOrientation(LinearLayout.VERTICAL)
  card.setPadding(dp(16), dp(16), dp(16), dp(16))
  card.setBackground(makeGradBg(startHex, endHex, 20, borderHex, strokeDp or 1.6))
  return card
end

-- 1. Hero Header Card (Royal Plum & Gold)
local headerCard = makeSectionCard("#3B0764", "#1A0B2E", "#F59E0B", 1.8)
local titleTv = TextView(activity)
titleTv.setText(TOOL_TITLE)
titleTv.setTextColor(Color.parseColor("#FFFFFF"))
titleTv.setTextSize(23)
titleTv.setTypeface(Typeface.DEFAULT_BOLD)
titleTv.setContentDescription(TOOL_TITLE)
setHeading(titleTv)
headerCard.addView(titleTv)

local devTv = TextView(activity)
devTv.setText(DEV_NAME)
devTv.setTextColor(Color.parseColor("#FDE68A"))
devTv.setTextSize(14)
devTv.setTypeface(Typeface.DEFAULT_BOLD)
devTv.setPadding(0, dp(5), 0, 0)
devTv.setContentDescription(DEV_NAME)
setHeading(devTv)
headerCard.addView(devTv)

mainBox.addView(headerCard)
addGap(mainBox, 14)

-- 2. Select Mode Spinner Card (Crimson-Rose Theme)
local modeCard = makeSectionCard("#2D0A1B", "#16050D", "#F43F5E", 1.5)

local modeLabel = TextView(activity)
modeLabel.setText("Select Mode")
modeLabel.setTextColor(Color.parseColor("#FECDD3"))
modeLabel.setTextSize(15)
modeLabel.setTypeface(Typeface.DEFAULT_BOLD)
modeLabel.setPadding(0, 0, 0, dp(8))
setHeading(modeLabel)
modeCard.addView(modeLabel)

local modeList = ArrayList()
modeList.add("Text to Video")
modeList.add("Audio to Video")

local modeAdapter = ArrayAdapter(activity, android.R.layout.simple_spinner_item, modeList)
modeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)

local modeSpinner = Spinner(activity)
modeSpinner.setAdapter(modeAdapter)
modeSpinner.setPadding(dp(12), dp(10), dp(12), dp(10))
modeSpinner.setBackground(makeCardBg("#4C0D29", 13, "#FB7185", 1.3))
modeSpinner.setContentDescription("Select Mode")
modeCard.addView(modeSpinner, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

mainBox.addView(modeCard)
addGap(mainBox, 14)

-- 3. Input Card (Espresso & Amber — switches cleanly between empty Text Box and SELECT AUDIO)
local inputCard = makeSectionCard("#1F160A", "#120C05", "#F59E0B", 1.5)

local etScript = EditText(activity)
etScript.setTextColor(Color.parseColor("#FFFFFF"))
etScript.setTextSize(14)
etScript.setMinLines(6)
etScript.setMaxLines(12)
etScript.setGravity(Gravity.TOP | Gravity.LEFT)
etScript.setPadding(dp(14), dp(14), dp(14), dp(14))
etScript.setBackground(makeCardBg("#0C0804", 14, "#B45309", 1.3))
etScript.setContentDescription("Text input")
inputCard.addView(etScript)

local btnSelectAudio = Button(activity)
btnSelectAudio.setText("SELECT AUDIO")
btnSelectAudio.setAllCaps(false)
btnSelectAudio.setTextColor(Color.parseColor("#041413"))
btnSelectAudio.setTextSize(15)
btnSelectAudio.setTypeface(Typeface.DEFAULT_BOLD)
btnSelectAudio.setPadding(dp(15), dp(15), dp(15), dp(15))
btnSelectAudio.setBackground(makeGradBg("#2DD4BF", "#0D9488", 14, "#CCFBF1", 1.4))
btnSelectAudio.setVisibility(View.GONE)
inputCard.addView(btnSelectAudio, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

mainBox.addView(inputCard)
addGap(mainBox, 14)

-- 4. Studio Settings & Generate Card (Deep Forest Emerald & Mint)
local settingsCard = makeSectionCard("#07221B", "#041410", "#10B981", 1.5)

local settingsHeading = TextView(activity)
settingsHeading.setText("Studio Settings")
settingsHeading.setTextColor(Color.parseColor("#A7F3D0"))
settingsHeading.setTextSize(17)
settingsHeading.setTypeface(Typeface.DEFAULT_BOLD)
setHeading(settingsHeading)
settingsCard.addView(settingsHeading)

local function makePickerBtn(labelText, startHex, endHex, borderHex, onClickFn)
  local btn = Button(activity)
  btn.setText(labelText)
  btn.setAllCaps(false)
  btn.setTextColor(Color.parseColor("#FFFFFF"))
  btn.setTextSize(14)
  btn.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL)
  btn.setPadding(dp(15), dp(13), dp(15), dp(13))
  btn.setBackground(makeGradBg(startHex, endHex, 14, borderHex, 1.3))
  local lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lp.topMargin = dp(10)
  btn.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      onClickFn(btn)
    end
  })
  settingsCard.addView(btn, lp)
  return btn
end

local function showStyledPickerWindow(title, subtitle, items, currentIdx, accentHex, bgStart, bgEnd, cardBgHex, cardBrdHex, onPicked)
  local wrap = LinearLayout(activity)
  wrap.setOrientation(LinearLayout.VERTICAL)
  wrap.setPadding(dp(18), dp(18), dp(18), dp(18))
  wrap.setBackground(makeGradBg(bgStart, bgEnd, 22, accentHex, 2.0))

  local hTv = TextView(activity)
  hTv.setText(title)
  hTv.setTextColor(Color.parseColor("#FFFFFF"))
  hTv.setTextSize(19)
  hTv.setTypeface(Typeface.DEFAULT_BOLD)
  setHeading(hTv)
  wrap.addView(hTv)

  local sTv = TextView(activity)
  sTv.setText(subtitle)
  sTv.setTextColor(Color.parseColor("#E2E8F0"))
  sTv.setTextSize(13)
  sTv.setPadding(0, dp(4), 0, dp(14))
  sTv.setFocusable(true)
  wrap.addView(sTv)

  local listSv = ScrollView(activity)
  local listBox = LinearLayout(activity)
  listBox.setOrientation(LinearLayout.VERTICAL)
  listSv.addView(listBox)

  local dlg = nil
  for i, itemLabel in ipairs(items) do
    local isSel = (i == currentIdx)
    local b = Button(activity)
    b.setText((isSel and "✓  " or "") .. itemLabel)
    b.setAllCaps(false)
    b.setGravity(Gravity.LEFT | Gravity.CENTER_VERTICAL)
    b.setTextSize(14)
    b.setTypeface(isSel and Typeface.DEFAULT_BOLD or Typeface.DEFAULT)
    b.setTextColor(Color.parseColor(isSel and "#09090B" or "#FFFFFF"))
    b.setPadding(dp(14), dp(12), dp(14), dp(12))
    if isSel then
      b.setBackground(makeCardBg(accentHex, 13, "#FFFFFF", 1.4))
    else
      b.setBackground(makeCardBg(cardBgHex, 13, cardBrdHex, 1.1))
    end
    local lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
    lp.bottomMargin = dp(8)
    b.setOnClickListener(View.OnClickListener{
      onClick = function()
        haptic(35)
        onPicked(i)
        if dlg then dlg.dismiss() end
      end
    })
    listBox.addView(b, lp)
  end

  wrap.addView(listSv, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

  local btnCancel = Button(activity)
  btnCancel.setText("CLOSE")
  btnCancel.setAllCaps(false)
  btnCancel.setTextColor(Color.parseColor("#F8FAFC"))
  btnCancel.setTextSize(14)
  btnCancel.setTypeface(Typeface.DEFAULT_BOLD)
  btnCancel.setPadding(dp(12), dp(11), dp(12), dp(11))
  btnCancel.setBackground(makeCardBg("#27272A", 13, "#52525B", 1.2))
  local lpC = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpC.topMargin = dp(8)
  btnCancel.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      if dlg then dlg.dismiss() end
    end
  })
  wrap.addView(btnCancel, lpC)

  dlg = showStyledDialog(wrap)
end

local btnFormat, btnStyle, btnVoice, btnTrans, btnSubs

btnFormat = makePickerBtn("Format: " .. FORMATS[selectedFormatIdx].label, "#291B07", "#1A1104", "#F59E0B", function()
  local labels = {}
  for i, v in ipairs(FORMATS) do labels[i] = v.label end
  showStyledPickerWindow("Video Format", "Choose screen size for your video", labels, selectedFormatIdx, "#FBBF24", "#2B1B05", "#140C02", "#1F1406", "#78350F", function(idx)
    selectedFormatIdx = idx
    btnFormat.setText("Format: " .. FORMATS[idx].label)
  end)
end)

btnStyle = makePickerBtn("Visual Style: " .. VISUAL_STYLES[selectedStyleIdx].label, "#2E0B1E", "#190611", "#F43F5E", function()
  local labels = {}
  for i, v in ipairs(VISUAL_STYLES) do labels[i] = v.label end
  showStyledPickerWindow("Visual Style", "Select artistic look for scenes", labels, selectedStyleIdx, "#FB7185", "#330B20", "#17050F", "#240817", "#881337", function(idx)
    selectedStyleIdx = idx
    btnStyle.setText("Visual Style: " .. VISUAL_STYLES[idx].label)
  end)
end)

btnVoice = makePickerBtn("Narrator Voice: " .. VOICES[selectedVoiceIdx].label, "#0A2A22", "#061A15", "#10B981", function()
  local labels = {}
  for i, v in ipairs(VOICES) do labels[i] = v.label end
  showStyledPickerWindow("Narrator Voice", "Choose voiceover language and tone", labels, selectedVoiceIdx, "#34D399", "#072B22", "#041612", "#0B201B", "#065F46", function(idx)
    selectedVoiceIdx = idx
    btnVoice.setText("Narrator Voice: " .. VOICES[idx].label)
  end)
end)

btnTrans = makePickerBtn("Transition: " .. TRANSITIONS[selectedTransIdx].label, "#291224", "#170914", "#EC4899", function()
  local labels = {}
  for i, v in ipairs(TRANSITIONS) do labels[i] = v.label end
  showStyledPickerWindow("Scene Transition", "Choose how scenes blend into each other", labels, selectedTransIdx, "#F472B6", "#300E28", "#160613", "#240A1E", "#9D174D", function(idx)
    selectedTransIdx = idx
    btnTrans.setText("Transition: " .. TRANSITIONS[idx].label)
  end)
end)

btnSubs = makePickerBtn(SUB_MODES[selectedSubIdx].label, "#22103B", "#130922", "#A855F7", function()
  local labels = {}
  for i, v in ipairs(SUB_MODES) do labels[i] = v.label end
  showStyledPickerWindow("On-Screen Subtitles", "Display narration text on video", labels, selectedSubIdx, "#C084FC", "#271145", "#120721", "#1B0C30", "#6B21A8", function(idx)
    selectedSubIdx = idx
    btnSubs.setText(SUB_MODES[idx].label)
  end)
end)

local modeSpinnerReady = false
modeSpinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
  onItemSelected = function(parent, view, pos, id)
    pcall(function()
      if view and view.setTextColor then
        view.setTextColor(Color.parseColor("#FFFFFF"))
        view.setTextSize(15)
        view.setTypeface(Typeface.DEFAULT_BOLD)
      end
    end)
    if modeSpinnerReady then haptic(35) end
    modeSpinnerReady = true
    if pos == 0 then
      currentMode = "text"
      etScript.setVisibility(View.VISIBLE)
      btnSelectAudio.setVisibility(View.GONE)
      btnVoice.setVisibility(View.VISIBLE)
    else
      currentMode = "audio"
      etScript.setVisibility(View.GONE)
      btnSelectAudio.setVisibility(View.VISIBLE)
      btnVoice.setVisibility(View.GONE)
    end
  end,
  onNothingSelected = function() end
})

btnSelectAudio.setOnClickListener(View.OnClickListener{
  onClick = function()
    haptic(35)
    showInToolAudioPicker(function(path, name)
      selectedAudioPath = path
      selectedAudioName = name
      btnSelectAudio.setText("Selected Audio: " .. name)
    end)
  end
})

-- Vibrant Sunset Orange-to-Rose Generate Button
local btnGenerate = Button(activity)
btnGenerate.setText("GENERATE FULL VIDEO")
btnGenerate.setAllCaps(false)
btnGenerate.setTextColor(Color.parseColor("#FFFFFF"))
btnGenerate.setTextSize(16)
btnGenerate.setTypeface(Typeface.DEFAULT_BOLD)
btnGenerate.setPadding(dp(14), dp(15), dp(14), dp(15))
btnGenerate.setBackground(makeGradBg("#F97316", "#E11D48", 15, "#FDE68A", 1.6))
local lpGen = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
lpGen.topMargin = dp(16)
settingsCard.addView(btnGenerate, lpGen)

mainBox.addView(settingsCard)
addGap(mainBox, 16)

-- 5. Royal Violet ABOUT Button
local btnAbout = Button(activity)
btnAbout.setText("ABOUT")
btnAbout.setAllCaps(false)
btnAbout.setTextColor(Color.parseColor("#F3E8FF"))
btnAbout.setTextSize(15)
btnAbout.setTypeface(Typeface.DEFAULT_BOLD)
btnAbout.setPadding(dp(14), dp(14), dp(14), dp(14))
btnAbout.setBackground(makeGradBg("#581C87", "#3B0764", 15, "#C084FC", 1.4))
mainBox.addView(btnAbout, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))

activity.setContentView(rootScroll)

-- ==========================================
-- RENAME WINDOW (Rose-Gold & Plum Theme)
-- ==========================================
local function showRenameWindow(onRenamed)
  local wrap = LinearLayout(activity)
  wrap.setOrientation(LinearLayout.VERTICAL)
  wrap.setPadding(dp(18), dp(18), dp(18), dp(18))
  wrap.setBackground(makeGradBg("#2D0E2E", "#140617", 22, "#EC4899", 2.0))

  local h = TextView(activity)
  h.setText("Rename Video")
  h.setTextColor(Color.parseColor("#FCE7F3"))
  h.setTextSize(19)
  h.setTypeface(Typeface.DEFAULT_BOLD)
  setHeading(h)
  wrap.addView(h)

  local sub = TextView(activity)
  sub.setText("Enter a new filename for your video:")
  sub.setTextColor(Color.parseColor("#E2E8F0"))
  sub.setTextSize(13)
  sub.setPadding(0, dp(4), 0, dp(12))
  sub.setFocusable(true)
  wrap.addView(sub)

  local inp = EditText(activity)
  inp.setText(currentVideoTitle)
  inp.setSingleLine(true)
  inp.setTextColor(Color.parseColor("#FFFFFF"))
  inp.setTextSize(14)
  inp.setPadding(dp(14), dp(12), dp(14), dp(12))
  inp.setBackground(makeCardBg("#110514", 12, "#DB2777", 1.3))
  wrap.addView(inp)

  local row = LinearLayout(activity)
  row.setOrientation(LinearLayout.HORIZONTAL)
  local lpRow = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpRow.topMargin = dp(14)

  local dlg = nil

  local bSave = Button(activity)
  bSave.setText("SAVE NAME")
  bSave.setAllCaps(false)
  bSave.setTextColor(Color.parseColor("#FFFFFF"))
  bSave.setTypeface(Typeface.DEFAULT_BOLD)
  bSave.setBackground(makeGradBg("#DB2777", "#9D174D", 12, "#F9A8D4", 1.3))
  local lp1 = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1)
  lp1.rightMargin = dp(6)
  bSave.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      local newName = inp.getText().toString():gsub("[^%w%-%_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if newName ~= "" then
        currentVideoTitle = newName
        if onRenamed then onRenamed(currentVideoTitle) end
      end
      if dlg then dlg.dismiss() end
    end
  })
  row.addView(bSave, lp1)

  local bCan = Button(activity)
  bCan.setText("CANCEL")
  bCan.setAllCaps(false)
  bCan.setTextColor(Color.parseColor("#F1F5F9"))
  bCan.setTypeface(Typeface.DEFAULT_BOLD)
  bCan.setBackground(makeCardBg("#27272A", 12, "#52525B", 1.1))
  local lp2 = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1)
  lp2.leftMargin = dp(6)
  bCan.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      if dlg then dlg.dismiss() end
    end
  })
  row.addView(bCan, lp2)

  wrap.addView(row, lpRow)
  dlg = showStyledDialog(wrap)
end

-- ==========================================
-- VIDEO READY & CINEMA PLAYER WINDOW (Luxury Emerald & Gold Theme)
-- ==========================================
local function showVideoResultWindow(sceneCount)
  if welcomePlayer then
    pcall(function() welcomePlayer.stop() welcomePlayer.release() end)
    welcomePlayer = nil
  end

  local sv = ScrollView(activity)
  local wrap = LinearLayout(activity)
  wrap.setOrientation(LinearLayout.VERTICAL)
  wrap.setPadding(dp(18), dp(18), dp(18), dp(18))
  wrap.setBackground(makeGradBg("#062B22", "#041410", 22, "#10B981", 2.0))
  sv.addView(wrap)

  local topCard = LinearLayout(activity)
  topCard.setOrientation(LinearLayout.VERTICAL)
  topCard.setPadding(dp(15), dp(13), dp(15), dp(13))
  topCard.setBackground(makeGradBg("#0B3B2E", "#07261E", 15, "#F59E0B", 1.4))

  local hTv = TextView(activity)
  hTv.setText("Video Ready!")
  hTv.setTextColor(Color.parseColor("#FDE68A"))
  hTv.setTextSize(20)
  hTv.setTypeface(Typeface.DEFAULT_BOLD)
  setHeading(hTv)
  topCard.addView(hTv)

  local nameTv = TextView(activity)
  nameTv.setText(currentVideoTitle .. ".mp4  (" .. tostring(sceneCount) .. " Story Scenes)")
  nameTv.setTextColor(Color.parseColor("#ECFDF5"))
  nameTv.setTextSize(13)
  nameTv.setPadding(0, dp(4), 0, 0)
  nameTv.setFocusable(true)
  topCard.addView(nameTv)

  wrap.addView(topCard)
  addGap(wrap, 12)

  local frameCard = LinearLayout(activity)
  frameCard.setOrientation(LinearLayout.VERTICAL)
  frameCard.setPadding(dp(6), dp(6), dp(6), dp(6))
  frameCard.setBackground(makeCardBg("#000000", 15, "#34D399", 1.5))

  local vv = VideoView(activity)
  frameCard.addView(vv, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(250)))
  wrap.addView(frameCard)
  addGap(wrap, 12)

  local saveMsgTv = TextView(activity)
  saveMsgTv.setText("Preview your video above, rename it, or save directly to Downloads.")
  saveMsgTv.setTextColor(Color.parseColor("#D1FAE5"))
  saveMsgTv.setTextSize(13)
  saveMsgTv.setPadding(dp(4), 0, dp(4), dp(8))
  saveMsgTv.setFocusable(true)
  wrap.addView(saveMsgTv)

  local function makeResBtn(txt, sHex, eHex, brdHex, tHex)
    local b = Button(activity)
    b.setText(txt)
    b.setAllCaps(false)
    b.setTextColor(Color.parseColor(tHex or "#FFFFFF"))
    b.setTextSize(14)
    b.setTypeface(Typeface.DEFAULT_BOLD)
    b.setPadding(dp(12), dp(12), dp(12), dp(12))
    b.setBackground(makeGradBg(sHex, eHex, 13, brdHex, 1.3))
    local lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
    lp.topMargin = dp(9)
    wrap.addView(b, lp)
    return b
  end

  local btnPlayPause = makeResBtn("PAUSE VIDEO", "#10B981", "#059669", "#A7F3D0", "#03150E")
  local btnDl        = makeResBtn("DOWNLOAD MP4", "#F59E0B", "#D97706", "#FDE68A", "#1C0F02")
  local btnRen       = makeResBtn("RENAME VIDEO", "#DB2777", "#9D174D", "#F9A8D4", "#FFFFFF")
  local btnClose     = makeResBtn("CLOSE", "#27272A", "#18181B", "#52525B", "#F4F4F5")

  local dlg = showStyledDialog(sv)

  vv.setVideoPath(currentVideoPath)
  vv.setOnCompletionListener(MediaPlayer.OnCompletionListener{
    onCompletion = function()
      btnPlayPause.setText("PLAY AGAIN")
    end
  })
  vv.start()

  btnPlayPause.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      if vv.isPlaying() then
        vv.pause()
        btnPlayPause.setText("PLAY VIDEO")
      else
        vv.start()
        btnPlayPause.setText("PAUSE VIDEO")
      end
    end
  })

  btnDl.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      if not currentVideoPath or not File(currentVideoPath).exists() then return end
      File(DOWNLOAD_DIR).mkdirs()
      local destPath = DOWNLOAD_DIR .. "/" .. currentVideoTitle .. ".mp4"
      local ok = pcall(function()
        local inp = FileInputStream(currentVideoPath)
        local out = FileOutputStream(destPath)
        local buf = byte[8192]
        local n = inp.read(buf)
        while n ~= -1 do
          out.write(buf, 0, n)
          n = inp.read(buf)
        end
        out.flush()
        out.close()
        inp.close()
        MediaScannerConnection.scanFile(activity, String({destPath}), nil, nil)
      end)
      if ok then
        saveMsgTv.setText("Saved to Download/AI_Video_Maker_Studio/" .. currentVideoTitle .. ".mp4")
        Toast.makeText(activity, "Video saved to Downloads.", Toast.LENGTH_SHORT).show()
      else
        Toast.makeText(activity, "Could not save video. Check storage permission.", Toast.LENGTH_SHORT).show()
      end
    end
  })

  btnRen.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      showRenameWindow(function(newName)
        nameTv.setText(newName .. ".mp4  (" .. tostring(sceneCount) .. " Story Scenes)")
        saveMsgTv.setText("Renamed to: " .. newName .. ".mp4")
      end)
    end
  })

  btnClose.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      pcall(function() vv.stopPlayback() end)
      dlg.dismiss()
    end
  })
end

-- ==========================================
-- ERROR WINDOW (Deep Crimson Theme)
-- ==========================================
local function showErrorWindow(errText)
  local wrap = LinearLayout(activity)
  wrap.setOrientation(LinearLayout.VERTICAL)
  wrap.setPadding(dp(18), dp(18), dp(18), dp(18))
  wrap.setBackground(makeGradBg("#330A14", "#170409", 22, "#F43F5E", 2.0))

  local h = TextView(activity)
  h.setText("Generation Failed")
  h.setTextColor(Color.parseColor("#FDA4AF"))
  h.setTextSize(19)
  h.setTypeface(Typeface.DEFAULT_BOLD)
  setHeading(h)
  wrap.addView(h)

  local b = TextView(activity)
  b.setText(tostring(errText))
  b.setTextColor(Color.parseColor("#FFE4E6"))
  b.setTextSize(14)
  b.setPadding(0, dp(8), 0, dp(14))
  b.setFocusable(true)
  wrap.addView(b)

  local dlg = nil
  local btnOk = Button(activity)
  btnOk.setText("CLOSE")
  btnOk.setAllCaps(false)
  btnOk.setTextColor(Color.parseColor("#FFFFFF"))
  btnOk.setTypeface(Typeface.DEFAULT_BOLD)
  btnOk.setBackground(makeGradBg("#E11D48", "#9F1239", 13, "#FDA4AF", 1.3))
  btnOk.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      if dlg then dlg.dismiss() end
    end
  })
  wrap.addView(btnOk)
  dlg = showStyledDialog(wrap)
end

-- ==========================================
-- DUAL-MODE FULL VIDEO GENERATOR WORKER
-- ==========================================
local function startVideoGeneration(modeId, inputVal)
  isGenerating = true
  isHiddenInBackground = false
  btnGenerate.setEnabled(false)

  local fmt = FORMATS[selectedFormatIdx]
  local sty = VISUAL_STYLES[selectedStyleIdx]
  local vce = VOICES[selectedVoiceIdx]
  local transId = TRANSITIONS[selectedTransIdx].id
  local showSubs = SUB_MODES[selectedSubIdx].enabled

  local pf = io.open(progressFile, "w")
  if pf then pf:write("Preparing studio engine...") pf:close() end

  local pWrap = LinearLayout(activity)
  pWrap.setOrientation(LinearLayout.VERTICAL)
  pWrap.setPadding(dp(20), dp(20), dp(20), dp(20))
  pWrap.setBackground(makeGradBg("#291A07", "#140C03", 22, "#F59E0B", 2.0))

  local pHead = TextView(activity)
  pHead.setText("Creating Your Full Video")
  pHead.setTextColor(Color.parseColor("#FDE68A"))
  pHead.setTextSize(19)
  pHead.setTypeface(Typeface.DEFAULT_BOLD)
  setHeading(pHead)
  pWrap.addView(pHead)

  local pCard = LinearLayout(activity)
  pCard.setOrientation(LinearLayout.VERTICAL)
  pCard.setPadding(dp(15), dp(14), dp(15), dp(14))
  pCard.setBackground(makeCardBg("#160E04", 15, "#D97706", 1.3))
  local lpPC = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpPC.topMargin = dp(12)

  local pStatusTv = TextView(activity)
  pStatusTv.setText("Preparing studio engine...")
  pStatusTv.setTextColor(Color.parseColor("#FFFFFF"))
  pStatusTv.setTextSize(14)
  pStatusTv.setTypeface(Typeface.DEFAULT_BOLD)
  pStatusTv.setFocusable(true)
  pCard.addView(pStatusTv)

  local pNoteTv = TextView(activity)
  pNoteTv.setText("Tap HIDE below to return to your Home Screen while rendering continues in the background. You will be notified and the tool will reopen automatically once ready.")
  pNoteTv.setTextColor(Color.parseColor("#D6D3D1"))
  pNoteTv.setTextSize(12)
  pNoteTv.setPadding(0, dp(8), 0, 0)
  pNoteTv.setFocusable(true)
  pCard.addView(pNoteTv)

  pWrap.addView(pCard, lpPC)

  local btnHide = Button(activity)
  btnHide.setText("HIDE")
  btnHide.setAllCaps(false)
  btnHide.setTextColor(Color.parseColor("#FFFFFF"))
  btnHide.setTextSize(15)
  btnHide.setTypeface(Typeface.DEFAULT_BOLD)
  btnHide.setPadding(dp(14), dp(13), dp(14), dp(13))
  btnHide.setBackground(makeGradBg("#7C3AED", "#5B21B6", 13, "#C4B5FD", 1.3))
  local lpHide = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpHide.topMargin = dp(14)
  btnHide.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      isHiddenInBackground = true
      Toast.makeText(activity, "Running in background. Will auto-open when video is ready.", Toast.LENGTH_SHORT).show()
      hideToHomeScreen()
    end
  })
  pWrap.addView(btnHide, lpHide)

  local progressDlg = AlertDialog.Builder(activity).setView(pWrap).setCancelable(false).create()
  pcall(function()
    if progressDlg.getWindow() then
      progressDlg.getWindow().setBackgroundDrawableResource(android.R.color.transparent)
    end
  end)
  progressDlg.show()

  if statusTicker then pcall(function() statusTicker.stop() end) end
  statusTicker = Ticker()
  statusTicker.Period = 700
  statusTicker.onTick = function()
    local f = io.open(progressFile, "r")
    if f then
      local txt = f:read("*a")
      f:close()
      if txt and txt ~= "" then
        pStatusTv.setText(txt)
      end
    end
  end
  statusTicker.start()

  task(function(runMode, inputData, vidW, vidH, stylePrompt, voiceId, transMode, drawSubs, cacheDir, progPath)
    require "import"
    import "java.io.*"
    import "java.net.*"
    import "java.lang.*"
    import "java.nio.*"
    import "org.json.*"
    import "android.graphics.*"
    import "android.text.*"
    import "android.media.*"

    local function setProgress(msg)
      local f = io.open(progPath, "w")
      if f then f:write(msg) f:close() end
    end

    local function sleepMs(ms)
      pcall(function() Thread.sleep(ms) end)
    end

    local function urlEncode(str)
      return URLEncoder.encode(str or "", "UTF-8"):gsub("+", "%%20")
    end

    local function hasUrduChars(s)
      for i = 1, #s do
        local b = string.byte(s, i)
        if b and b >= 216 and b <= 219 then return true end
      end
      return false
    end

    local function hasDevanagariChars(s)
      for i = 1, #s - 1 do
        local b1, b2 = string.byte(s, i), string.byte(s, i + 1)
        if b1 == 224 and (b2 == 164 or b2 == 165) then return true end
      end
      return false
    end

    local function hasNonAsciiChars(s)
      for i = 1, #s do
        local b = string.byte(s, i)
        if b and b > 127 then return true end
      end
      return false
    end

    local function cleanWhisperTranscript(txt)
      if not txt or txt == "" then return "" end
      txt = txt:gsub("\239\191\189", ""):gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

      local words = {}
      for w in txt:gmatch("%S+") do
        words[#words + 1] = w
      end
      if #words == 0 then return "" end

      local dedup1 = {}
      for i = 1, #words do
        if i == 1 or words[i] ~= words[i - 1] then
          dedup1[#dedup1 + 1] = words[i]
        end
      end

      local out = {}
      local idx = 1
      while idx <= #dedup1 do
        local skipped = false
        for plen = 8, 2, -1 do
          if #out >= plen and (idx + plen - 1) <= #dedup1 then
            local match = true
            for k = 0, plen - 1 do
              if out[#out - plen + 1 + k] ~= dedup1[idx + k] then
                match = false
                break
              end
            end
            if match then
              idx = idx + plen
              skipped = true
              break
            end
          end
        end
        if not skipped then
          out[#out + 1] = dedup1[idx]
          idx = idx + 1
        end
      end

      return table.concat(out, " ")
    end

    local function downloadBinary(urlStr, outPath, timeoutMs, minSize)
      local complete = false
      local ok = pcall(function()
        local conn = URL(urlStr).openConnection()
        conn.setConnectTimeout(15000)
        conn.setReadTimeout(timeoutMs or 55000)
        conn.setInstanceFollowRedirects(true)
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13)")
        local code = conn.getResponseCode()
        local expectedLen = conn.getContentLength()
        if code >= 200 and code < 300 then
          local inp = BufferedInputStream(conn.getInputStream())
          local out = FileOutputStream(outPath)
          local buf = byte[8192]
          local totalRead = 0
          local n = inp.read(buf)
          while n ~= -1 do
            out.write(buf, 0, n)
            totalRead = totalRead + n
            n = inp.read(buf)
          end
          out.flush()
          out.close()
          inp.close()
          if totalRead >= (minSize or 1500) and (expectedLen <= 0 or totalRead >= expectedLen) then
            complete = true
          end
        end
        conn.disconnect()
      end)
      if not (ok and complete and File(outPath).exists()) then
        pcall(function() File(outPath).delete() end)
        return false
      end
      return true
    end

    local function httpRequest(urlStr, method, bodyStr, headers, timeoutMs)
      local url = URL(urlStr)
      local conn = url.openConnection()
      conn.setRequestMethod(method or "GET")
      conn.setConnectTimeout(15000)
      conn.setReadTimeout(timeoutMs or 60000)
      conn.setInstanceFollowRedirects(true)
      conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13)")
      if headers then
        for k, v in pairs(headers) do conn.setRequestProperty(k, v) end
      end
      if bodyStr then
        conn.setDoOutput(true)
        local os = conn.getOutputStream()
        os.write(String(bodyStr).getBytes("UTF-8"))
        os.flush()
        os.close()
      end
      local code = conn.getResponseCode()
      local stream = (code >= 200 and code < 400) and conn.getInputStream() or conn.getErrorStream()
      if not stream then conn.disconnect() return code, "" end
      local reader = BufferedReader(InputStreamReader(stream, "UTF-8"))
      local sb = StringBuilder()
      local line = reader.readLine()
      while line ~= nil do
        sb.append(line).append("\n")
        line = reader.readLine()
      end
      reader.close()
      conn.disconnect()
      return code, sb.toString()
    end

    local function transcribeAudioFile(audioPath)
      local spaces = {
        "https://hf-audio-whisper-large-v3-turbo.hf.space",
        "https://hf-audio-whisper-large-v3.hf.space",
        "https://openai-whisper.hf.space"
      }
      local fObj = File(audioPath)
      local fname = fObj.getName()

      for _, baseUrl in ipairs(spaces) do
        local okSp, transcript = pcall(function()
          local boundary = "----LuaBoundary" .. tostring(os.time())
          local conn = URL(baseUrl .. "/gradio_api/upload").openConnection()
          conn.setRequestMethod("POST")
          conn.setConnectTimeout(20000)
          conn.setReadTimeout(90000)
          conn.setDoOutput(true)
          conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" .. boundary)
          conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13)")

          local out = DataOutputStream(conn.getOutputStream())
          out.writeBytes("--" .. boundary .. "\r\n")
          out.writeBytes("Content-Disposition: form-data; name=\"files\"; filename=\"" .. fname .. "\"\r\n")
          out.writeBytes("Content-Type: application/octet-stream\r\n\r\n")
          local fis = FileInputStream(audioPath)
          local buf = byte[8192]
          local n = fis.read(buf)
          while n ~= -1 do
            out.write(buf, 0, n)
            n = fis.read(buf)
          end
          fis.close()
          out.writeBytes("\r\n--" .. boundary .. "--\r\n")
          out.flush()
          out.close()

          local uCode = conn.getResponseCode()
          if uCode < 200 or uCode >= 300 then conn.disconnect() return nil end
          local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
          local sb = StringBuilder()
          local ln = reader.readLine()
          while ln ~= nil do sb.append(ln) ln = reader.readLine() end
          reader.close()
          conn.disconnect()

          local upArr = JSONArray(sb.toString())
          if upArr.length() == 0 then return nil end
          local remotePath = upArr.getString(0)

          local fileData = JSONObject()
          fileData.put("path", remotePath)
          local meta = JSONObject()
          meta.put("_type", "gradio.FileData")
          fileData.put("meta", meta)

          local dataArr = JSONArray()
          dataArr.put(fileData)
          dataArr.put("transcribe")
          local postObj = JSONObject()
          postObj.put("data", dataArr)

          local callUrl = baseUrl .. "/gradio_api/call/predict"
          local pCode, pBody = httpRequest(callUrl, "POST", postObj.toString(), {["Content-Type"] = "application/json"}, 30000)
          if pCode < 200 or pCode >= 300 then
            callUrl = baseUrl .. "/gradio_api/call/transcribe"
            pCode, pBody = httpRequest(callUrl, "POST", postObj.toString(), {["Content-Type"] = "application/json"}, 30000)
          end
          if pCode < 200 or pCode >= 300 then return nil end

          local eid = JSONObject(pBody).optString("event_id", "")
          if eid == "" then return nil end

          local sCode, sBody = httpRequest(callUrl .. "/" .. eid, "GET", nil, nil, 150000)
          if sCode ~= 200 or not sBody then return nil end

          local lastEv = ""
          for line in sBody:gmatch("[^\r\n]+") do
            if line:find("^event:%s*") then
              lastEv = line:match("^event:%s*(.+)")
            elseif line:find("^data:%s*") and lastEv == "complete" then
              local dpStr = line:match("^data:%s*(.+)")
              local arr = JSONArray(dpStr)
              for i = 0, arr.length() - 1 do
                local v = arr.optString(i, "")
                if v and #v > 6 and not v:find("^http") then
                  return v
                end
              end
            end
          end
          return nil
        end)
        if okSp and transcript and #transcript > 6 then
          return transcript
        end
      end
      return nil
    end

    local function translateChunk(text, targetLang)
      if not text or text == "" then return "" end
      local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=" .. targetLang .. "&dt=t&q=" .. urlEncode(text)
      local ok, code, raw = pcall(httpRequest, url, "GET", nil, nil, 15000)
      if ok and code == 200 and raw then
        local okJ, translated = pcall(function()
          local arr = JSONArray(raw)
          local parts = arr.getJSONArray(0)
          local out = {}
          for i = 0, parts.length() - 1 do
            local seg = parts.getJSONArray(i).optString(0, "")
            if seg ~= "" then out[#out + 1] = seg end
          end
          return table.concat(out, " ")
        end)
        if okJ and translated and #translated > 2 then
          return translated:gsub("[\r\n\"]", " "):gsub("%s+", " ")
        end
      end
      return text
    end

    local function translateLongText(text, targetLang)
      if #text <= 450 then
        return translateChunk(text, targetLang)
      end
      local chunks = {}
      local buf = ""
      for word in text:gmatch("%S+") do
        if #buf + #word + 1 > 450 and buf ~= "" then
          chunks[#chunks + 1] = translateChunk(buf, targetLang)
          buf = word
        else
          buf = (buf == "" and word or (buf .. " " .. word))
        end
      end
      if buf ~= "" then
        chunks[#chunks + 1] = translateChunk(buf, targetLang)
      end
      return table.concat(chunks, " ")
    end

    local function translateToEnglish(text)
      if not hasNonAsciiChars(text) then return text end
      return translateChunk(text, "en")
    end

    local function detectSituationTag(txt)
      local low = string.lower(txt or "")
      if low:find("صبح") or low:find("دھوپ") or low:find("چڑیوں") or low:find("باغ") or low:find("چائے") or low:find("morning") or low:find("sunrise") or low:find("garden") or low:find("birds") then return "morning" end
      if low:find("پولیس") or low:find("ایمبولینس") or low:find("سائرن") or low:find("police") or low:find("ambulance") or low:find("siren") then return "emergency" end
      if low:find("آگ") or low:find("دھماک") or low:find("شعلے") or low:find("fire") or low:find("explosion") or low:find("flames") then return "fire" end
      if low:find("بارش") or low:find("بجلی") or low:find("طوفان") or low:find("بادل") or low:find("rain") or low:find("lightning") or low:find("storm") then return "storm" end
      if low:find("درواز") or low:find("دستک") or low:find("اجنبی") or low:find("برامده") or low:find("برآمد") or low:find("door") or low:find("knock") or low:find("stranger") then return "door" end
      if low:find("سڑک") or low:find("گاڑی") or low:find("پہاڑ") or low:find("road") or low:find("street") or low:find("car") or low:find("mountain") then return "road" end
      if low:find("تہہ خان") or low:find("گودام") or low:find("قید") or low:find("basement") or low:find("warehouse") then return "basement" end
      if low:find("پستول") or low:find("گولی") or low:find("تھپڑ") or low:find("مکا") or low:find("gun") or low:find("pistol") or low:find("fight") then return "action" end
      if low:find("فون") or low:find("موبائل") or low:find("phone") or low:find("call") then return "phone" end
      if low:find("حویلی") or low:find("کمر") or low:find("کتاب") or low:find("کرسی") or low:find("mansion") or low:find("room") or low:find("book") then return "indoor" end
      return "general"
    end

    local function splitIntoLines(txt, isWideScript)
      local maxChunkBytes = isWideScript and 240 or 150
      local clean = txt:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("[ \t]+", " ")
      clean = clean:gsub("([%.%!%?])%s+", "%1\n")
      clean = clean:gsub("۔%s*", "۔\n")
      clean = clean:gsub("؟%s*", "؟\n")
      clean = clean:gsub("।%s*", "।\n")

      local rawParts = {}
      for line in clean:gmatch("[^\n]+") do
        local t = line:gsub("^%s+", ""):gsub("%s+$", "")
        if #t > 0 then rawParts[#rawParts + 1] = t end
      end

      local lines = {}
      for _, part in ipairs(rawParts) do
        if #part <= maxChunkBytes then
          lines[#lines + 1] = part
        else
          local buf = ""
          for word in part:gmatch("%S+") do
            if #buf + #word + 1 > maxChunkBytes and buf ~= "" then
              lines[#lines + 1] = buf
              buf = word
            else
              buf = (buf == "" and word or (buf .. " " .. word))
            end
          end
          if buf ~= "" then lines[#lines + 1] = buf end
        end
      end
      return lines
    end

    local runId = tostring(os.time())
    local workDir = cacheDir .. "/job_" .. runId
    File(workDir).mkdirs()

    local pcmPath = workDir .. "/master_audio.pcm"
    local pcmOut = FileOutputStream(pcmPath)
    local audioSampleRate = 24000
    local audioChannels = 1
    local gotFormat = false

    local function decodeAudioToPcm(audioFilePath, addPauseSec)
      local totalBytes = 0
      local extractor = MediaExtractor()
      extractor.setDataSource(audioFilePath)
      local trackIdx = -1
      local fmt = nil
      for i = 0, extractor.getTrackCount() - 1 do
        local f = extractor.getTrackFormat(i)
        local mime = f.getString(MediaFormat.KEY_MIME)
        if mime and mime:find("^audio/") then
          trackIdx = i
          fmt = f
          break
        end
      end
      if trackIdx < 0 then
        extractor.release()
        return 0
      end
      extractor.selectTrack(trackIdx)
      if not gotFormat then
        audioSampleRate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        audioChannels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        gotFormat = true
      end
      local mime = fmt.getString(MediaFormat.KEY_MIME)
      local decoder = MediaCodec.createDecoderByType(mime)
      decoder.configure(fmt, nil, nil, 0)
      decoder.start()

      local info = MediaCodec.BufferInfo()
      local inputDone = false
      local outputDone = false
      while not outputDone do
        if not inputDone then
          local inIdx = decoder.dequeueInputBuffer(10000)
          if inIdx >= 0 then
            local inBuf = decoder.getInputBuffer(inIdx)
            local sampleSize = extractor.readSampleData(inBuf, 0)
            if sampleSize < 0 then
              decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
              inputDone = true
            else
              local pts = extractor.getSampleTime()
              decoder.queueInputBuffer(inIdx, 0, sampleSize, pts, 0)
              extractor.advance()
            end
          end
        end
        local outIdx = decoder.dequeueOutputBuffer(info, 10000)
        if outIdx >= 0 then
          if info.size > 0 then
            local outBuf = decoder.getOutputBuffer(outIdx)
            outBuf.position(info.offset)
            outBuf.limit(info.offset + info.size)
            local chunk = byte[info.size]
            outBuf.get(chunk)
            pcmOut.write(chunk)
            totalBytes = totalBytes + info.size
          end
          decoder.releaseOutputBuffer(outIdx, false)
          if (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) ~= 0 then
            outputDone = true
          end
        elseif outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED then
          local of = decoder.getOutputFormat()
          if of.containsKey(MediaFormat.KEY_SAMPLE_RATE) then
            audioSampleRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE)
          end
          if of.containsKey(MediaFormat.KEY_CHANNEL_COUNT) then
            audioChannels = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
          end
        end
      end

      if addPauseSec and addPauseSec > 0 then
        local pauseBytes = math.floor(audioSampleRate * audioChannels * 2 * addPauseSec)
        if pauseBytes % 2 ~= 0 then pauseBytes = pauseBytes + 1 end
        local silence = byte[pauseBytes]
        pcmOut.write(silence)
        totalBytes = totalBytes + pauseBytes
      end

      pcall(function() decoder.stop() decoder.release() end)
      pcall(function() extractor.release() end)
      return totalBytes
    end

    local lineRecords = {}

    if runMode == "text" then
      local isUrduScript = (voiceId == "ur") or (voiceId == "auto" and hasUrduChars(inputData))
      local activeVoice = isUrduScript and "ur" or (voiceId == "auto" and "Matthew" or voiceId)
      local lines = splitIntoLines(inputData, isUrduScript or hasNonAsciiChars(inputData))
      if #lines == 0 then
        pcmOut.close()
        return false, "Script is empty."
      end

      local function fetchLineVoice(text, outMp3)
        local enc = urlEncode(text)
        if activeVoice == "ur" then
          return downloadBinary("https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=ur&q=" .. enc, outMp3, 25000, 800)
        else
          local ok = downloadBinary("https://api.streamelements.com/kappa/v2/speech?voice=" .. activeVoice .. "&text=" .. enc, outMp3, 25000, 800)
          if not ok then
            ok = downloadBinary("https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en-US&q=" .. enc, outMp3, 25000, 800)
          end
          return ok
        end
      end

      for i, sText in ipairs(lines) do
        setProgress(string.format("Recording Voice %d of %d...", i, #lines))
        local mp3Path = workDir .. "/voice_" .. i .. ".mp3"
        local vOk = fetchLineVoice(sText, mp3Path)
        if not vOk then
          sleepMs(1500)
          vOk = fetchLineVoice(sText, mp3Path)
        end
        if not vOk then
          pcmOut.close()
          return false, "Could not generate voice for line " .. tostring(i) .. ". Check internet."
        end
        local pcmBytes = decodeAudioToPcm(mp3Path, 0.30)
        local bytesPerSec = audioSampleRate * audioChannels * 2
        local durSec = math.max(1.2, pcmBytes / math.max(1, bytesPerSec))
        lineRecords[#lineRecords + 1] = {
          text = sText,
          durSec = durSec,
          sit = detectSituationTag(sText),
          imgPath = nil
        }
      end
    else
      setProgress("Analyzing your selected audio...")
      local pcmBytes = decodeAudioToPcm(inputData, 0)
      local bytesPerSec = audioSampleRate * audioChannels * 2
      local totalAudioSec = pcmBytes / math.max(1, bytesPerSec)
      if totalAudioSec < 1.0 then
        pcmOut.close()
        return false, "Could not decode the selected audio file."
      end

      setProgress("Listening to your audio to understand scenes...")
      local rawTranscript = transcribeAudioFile(inputData)
      if not rawTranscript or #rawTranscript < 4 then
        pcmOut.close()
        return false, "Could not recognize speech from this audio right now. Please check internet or toggle Airplane Mode for 3 seconds and retry."
      end

      local transcript = cleanWhisperTranscript(rawTranscript)

      if hasDevanagariChars(transcript) then
        setProgress("Preparing story scenes...")
        local urduConv = translateLongText(transcript, "ur")
        if urduConv and #urduConv > 4 then
          transcript = cleanWhisperTranscript(urduConv)
        end
      end

      local isWideT = hasNonAsciiChars(transcript)
      local lines = splitIntoLines(transcript, isWideT)
      local totalChars = 0
      for _, ln in ipairs(lines) do totalChars = totalChars + math.max(1, #ln) end

      for _, sText in ipairs(lines) do
        local frac = math.max(1, #sText) / math.max(1, totalChars)
        local durSec = math.max(1.5, totalAudioSec * frac)
        lineRecords[#lineRecords + 1] = {
          text = sText,
          durSec = durSec,
          sit = detectSituationTag(sText),
          imgPath = nil
        }
      end
    end

    pcmOut.flush()
    pcmOut.close()

    local visualGroups = {}
    local curGroup = {indices = {}, texts = {}, dur = 0, sit = nil}
    for i, rec in ipairs(lineRecords) do
      local sitChanged = (curGroup.sit ~= nil) and (rec.sit ~= "general") and (rec.sit ~= curGroup.sit) and (curGroup.dur >= 4.5)
      if sitChanged and #curGroup.indices > 0 then
        visualGroups[#visualGroups + 1] = curGroup
        curGroup = {indices = {}, texts = {}, dur = 0, sit = nil}
      end
      curGroup.indices[#curGroup.indices + 1] = i
      curGroup.texts[#curGroup.texts + 1] = rec.text
      curGroup.dur = curGroup.dur + rec.durSec
      if rec.sit ~= "general" then curGroup.sit = rec.sit end

      if curGroup.dur >= 12.0 or #curGroup.indices >= 2 or i == #lineRecords then
        visualGroups[#visualGroups + 1] = curGroup
        curGroup = {indices = {}, texts = {}, dur = 0, sit = nil}
      end
    end

    local function isValidFullImage(imgPath)
      local bmp = nil
      pcall(function() bmp = BitmapFactory.decodeFile(imgPath) end)
      if not bmp then return false end
      local tw, th = bmp.getWidth(), bmp.getHeight()
      local valid = false
      if tw >= 256 and th >= 256 then
        local yTest = math.floor(th * 0.78)
        local p1 = bmp.getPixel(math.floor(tw * 0.25), yTest)
        local p2 = bmp.getPixel(math.floor(tw * 0.50), yTest)
        local p3 = bmp.getPixel(math.floor(tw * 0.75), yTest)
        local function isPureBlack(c)
          return Color.red(c) <= 2 and Color.green(c) <= 2 and Color.blue(c) <= 2
        end
        if not (isPureBlack(p1) and isPureBlack(p2) and isPureBlack(p3)) then
          valid = true
        end
      end
      pcall(function() bmp.recycle() end)
      return valid
    end

    local function fetchVisualImage(combinedText, outJpg, sceneIdx)
      local engScene = translateToEnglish(combinedText)
      if #engScene > 200 then engScene = engScene:sub(1, 200) end
      local promptStr = "Cinematic movie frame depicting: " .. engScene .. ". " .. stylePrompt .. ", wide storytelling shot, no text, no watermark"
      local encPrompt = urlEncode(promptStr)
      local reqH = math.floor(vidH * 1.15)
      if reqH % 16 ~= 0 then reqH = reqH + (16 - (reqH % 16)) end
      local seed = tostring(os.time() + sceneIdx * 173)

      local urls = {
        "https://image.pollinations.ai/prompt/" .. encPrompt .. "?width=" .. vidW .. "&height=" .. reqH .. "&nologo=true&seed=" .. seed,
        "https://image.pollinations.ai/prompt/" .. encPrompt .. "?width=" .. vidW .. "&height=" .. reqH .. "&model=turbo&nologo=true&seed=" .. seed,
        "https://gen.pollinations.ai/image/" .. encPrompt .. "?width=" .. vidW .. "&height=" .. reqH .. "&nologo=true&seed=" .. seed,
        "https://image.pollinations.ai/prompt/" .. encPrompt .. "?width=" .. vidW .. "&height=" .. reqH .. "&model=flux&nologo=true&seed=" .. seed
      }
      local waits = {6000, 9000, 12000, 5000}

      for attempt = 1, 4 do
        if downloadBinary(urls[attempt], outJpg, 55000, 14000) and isValidFullImage(outJpg) then
          return true
        end
        pcall(function() File(outJpg).delete() end)
        sleepMs(waits[attempt])
      end
      return false
    end

    local firstGoodImgPath = nil
    local lastGoodImgPath = nil
    for gIdx, grp in ipairs(visualGroups) do
      setProgress(string.format("Generating Story Scene %d of %d...", gIdx, #visualGroups))
      local jpgPath = workDir .. "/scene_" .. gIdx .. ".jpg"
      local combinedTxt = table.concat(grp.texts, " ")
      local okImg = fetchVisualImage(combinedTxt, jpgPath, gIdx)
      if okImg then
        if not firstGoodImgPath then firstGoodImgPath = jpgPath end
        lastGoodImgPath = jpgPath
      end
      local assignedPath = okImg and jpgPath or lastGoodImgPath
      for _, lineIdx in ipairs(grp.indices) do
        lineRecords[lineIdx].imgPath = assignedPath
      end
      if gIdx < #visualGroups then
        sleepMs(8000)
      end
    end

    if firstGoodImgPath then
      for _, rec in ipairs(lineRecords) do
        if not rec.imgPath then rec.imgPath = firstGoodImgPath end
      end
    end

    setProgress("Encoding audio track...")
    local tempAudioM4a = workDir .. "/audio_only.m4a"
    local aacFmt = MediaFormat.createAudioFormat("audio/mp4a-latm", audioSampleRate, audioChannels)
    aacFmt.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
    aacFmt.setInteger(MediaFormat.KEY_BIT_RATE, 96000)
    aacFmt.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

    local aEncoder = MediaCodec.createEncoderByType("audio/mp4a-latm")
    aEncoder.configure(aacFmt, nil, nil, MediaCodec.CONFIGURE_FLAG_ENCODE)
    aEncoder.start()

    local aMuxer = MediaMuxer(tempAudioM4a, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    local aTrackIdx = -1
    local aMuxStarted = false

    local pcmIn = FileInputStream(pcmPath)
    local readBuf = byte[4096]
    local totalBytesFed = 0
    local bytesPerSec = audioSampleRate * audioChannels * 2
    local aInputDone = false
    local aOutputDone = false
    local aInfo = MediaCodec.BufferInfo()

    while not aOutputDone do
      if not aInputDone then
        local inIdx = aEncoder.dequeueInputBuffer(10000)
        if inIdx >= 0 then
          local inBuf = aEncoder.getInputBuffer(inIdx)
          inBuf.clear()
          local n = pcmIn.read(readBuf)
          if n == -1 then
            local ptsUs = math.floor((totalBytesFed / bytesPerSec) * 1000000)
            aEncoder.queueInputBuffer(inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            aInputDone = true
          else
            inBuf.put(readBuf, 0, n)
            local ptsUs = math.floor((totalBytesFed / bytesPerSec) * 1000000)
            aEncoder.queueInputBuffer(inIdx, 0, n, ptsUs, 0)
            totalBytesFed = totalBytesFed + n
          end
        end
      end

      local outIdx = aEncoder.dequeueOutputBuffer(aInfo, 10000)
      if outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED then
        aTrackIdx = aMuxer.addTrack(aEncoder.getOutputFormat())
        aMuxer.start()
        aMuxStarted = true
      elseif outIdx >= 0 then
        local outBuf = aEncoder.getOutputBuffer(outIdx)
        if (aInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) ~= 0 then
          aInfo.size = 0
        end
        if aInfo.size > 0 and aMuxStarted then
          outBuf.position(aInfo.offset)
          outBuf.limit(aInfo.offset + aInfo.size)
          aMuxer.writeSampleData(aTrackIdx, outBuf, aInfo)
        end
        aEncoder.releaseOutputBuffer(outIdx, false)
        if (aInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) ~= 0 then
          aOutputDone = true
        end
      end
    end

    pcmIn.close()
    pcall(function() aEncoder.stop() aEncoder.release() end)
    pcall(function() if aMuxStarted then aMuxer.stop() end aMuxer.release() end)

    setProgress("Rendering HD video frames...")
    local tempVideoMp4 = workDir .. "/video_only.mp4"
    local fps = 10
    local frameDurUs = math.floor(1000000 / fps)

    local vFmt = MediaFormat.createVideoFormat("video/avc", vidW, vidH)
    vFmt.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
    vFmt.setInteger(MediaFormat.KEY_BIT_RATE, 2500000)
    vFmt.setInteger(MediaFormat.KEY_FRAME_RATE, fps)
    vFmt.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)

    local vEncoder = MediaCodec.createEncoderByType("video/avc")
    vEncoder.configure(vFmt, nil, nil, MediaCodec.CONFIGURE_FLAG_ENCODE)
    local inputSurface = vEncoder.createInputSurface()
    vEncoder.start()

    local vMuxer = MediaMuxer(tempVideoMp4, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    local vTrackIdx = -1
    local vMuxStarted = false
    local vInfo = MediaCodec.BufferInfo()
    local encodedFrameCount = 0

    local function drainVideoEncoder(endOfStream)
      if endOfStream then
        vEncoder.signalEndOfInputStream()
      end
      while true do
        local outIdx = vEncoder.dequeueOutputBuffer(vInfo, endOfStream and 15000 or 2000)
        if outIdx == MediaCodec.INFO_TRY_AGAIN_LATER then
          if not endOfStream then break end
        elseif outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED then
          if not vMuxStarted then
            vTrackIdx = vMuxer.addTrack(vEncoder.getOutputFormat())
            vMuxer.start()
            vMuxStarted = true
          end
        elseif outIdx >= 0 then
          local outBuf = vEncoder.getOutputBuffer(outIdx)
          if (vInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) ~= 0 then
            vInfo.size = 0
          end
          if vInfo.size > 0 and vMuxStarted then
            outBuf.position(vInfo.offset)
            outBuf.limit(vInfo.offset + vInfo.size)
            vInfo.presentationTimeUs = encodedFrameCount * frameDurUs
            vMuxer.writeSampleData(vTrackIdx, outBuf, vInfo)
            encodedFrameCount = encodedFrameCount + 1
          end
          vEncoder.releaseOutputBuffer(outIdx, false)
          if (vInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) ~= 0 then
            break
          end
        end
      end
    end

    local function makeFallbackBitmap(w, h)
      local bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
      local cv = Canvas(bmp)
      local p = Paint()
      p.setShader(LinearGradient(0, 0, w, h, Color.parseColor("#18181B"), Color.parseColor("#27272A"), Shader.TileMode.CLAMP))
      cv.drawRect(0, 0, w, h, p)
      return bmp
    end

    local imgPaint = Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG)
    local fadePaint = Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG)
    local scrimPaint = Paint()
    local subBoxTop = math.floor(vidH * 0.72)
    scrimPaint.setShader(LinearGradient(0, subBoxTop, 0, vidH, Color.TRANSPARENT, Color.parseColor("#D9000000"), Shader.TileMode.CLAMP))

    local subPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    subPaint.setColor(Color.WHITE)
    subPaint.setTextSize(math.floor(math.min(vidW, vidH) * 0.050))
    subPaint.setTypeface(Typeface.DEFAULT_BOLD)
    subPaint.setShadowLayer(6.0, 2.0, 2.0, Color.BLACK)

    local cachedPath = nil
    local cachedBmp = nil
    local prevBmp = nil

    for sIdx, rec in ipairs(lineRecords) do
      setProgress(string.format("Rendering Video Part %d of %d...", sIdx, #lineRecords))

      local isSceneSwitch = false
      if (not cachedBmp) or (rec.imgPath ~= cachedPath) then
        if prevBmp then
          pcall(function() prevBmp.recycle() end)
          prevBmp = nil
        end
        if cachedBmp then
          prevBmp = cachedBmp
          cachedBmp = nil
          isSceneSwitch = true
        end
        cachedPath = rec.imgPath
        if rec.imgPath then
          local rawBmp = nil
          pcall(function() rawBmp = BitmapFactory.decodeFile(rec.imgPath) end)
          if rawBmp then
            local rw, rh = rawBmp.getWidth(), rawBmp.getHeight()
            local cropH = math.floor(rh * 0.88)
            if cropH > 64 then
              pcall(function()
                cachedBmp = Bitmap.createBitmap(rawBmp, 0, 0, rw, cropH)
              end)
            end
            if cachedBmp and cachedBmp ~= rawBmp then
              pcall(function() rawBmp.recycle() end)
            else
              cachedBmp = rawBmp
            end
          end
        end
        if not cachedBmp then
          cachedBmp = makeFallbackBitmap(vidW, vidH)
        end
      end

      local bw, bh = cachedBmp.getWidth(), cachedBmp.getHeight()
      local baseScale = math.max(vidW / bw, vidH / bh)
      local totalFrames = math.max(fps, math.floor(rec.durSec * fps + 0.5))
      local zoomIn = ((sIdx % 2) == 1)
      local fadeFrames = 8

      local subLayout = nil
      if drawSubs then
        local textW = math.floor(vidW * 0.88)
        subLayout = StaticLayout(rec.text, subPaint, textW, Layout.Alignment.ALIGN_CENTER, 1.15, 0.0, false)
      end

      for f = 0, totalFrames - 1 do
        local prog = f / math.max(1, totalFrames - 1)
        local zoom = zoomIn and (1.0 + 0.08 * prog) or (1.08 - 0.08 * prog)
        local scale = baseScale * zoom
        local drawW = bw * scale
        local drawH = bh * scale
        local dx = (vidW - drawW) / 2.0
        local dy = (vidH - drawH) / 2.0

        local canvas = inputSurface.lockCanvas(nil)
        if canvas then
          canvas.drawColor(Color.BLACK)

          if isSceneSwitch and prevBmp and transMode == "crossfade" and f < fadeFrames then
            local pw, ph = prevBmp.getWidth(), prevBmp.getHeight()
            local pScale = math.max(vidW / pw, vidH / ph) * 1.04
            local pMat = Matrix()
            pMat.postScale(pScale, pScale)
            pMat.postTranslate((vidW - pw * pScale) / 2.0, (vidH - ph * pScale) / 2.0)
            canvas.drawBitmap(prevBmp, pMat, imgPaint)

            fadePaint.setAlpha(math.floor(255 * ((f + 1) / fadeFrames)))
            local mat = Matrix()
            mat.postScale(scale, scale)
            mat.postTranslate(dx, dy)
            canvas.drawBitmap(cachedBmp, mat, fadePaint)
          elseif isSceneSwitch and prevBmp and transMode == "fadeblack" and f < fadeFrames then
            local half = math.floor(fadeFrames / 2)
            if f < half then
              local pw, ph = prevBmp.getWidth(), prevBmp.getHeight()
              local pScale = math.max(vidW / pw, vidH / ph) * 1.04
              local pMat = Matrix()
              pMat.postScale(pScale, pScale)
              pMat.postTranslate((vidW - pw * pScale) / 2.0, (vidH - ph * pScale) / 2.0)
              fadePaint.setAlpha(math.floor(255 * (1.0 - (f + 1) / half)))
              canvas.drawBitmap(prevBmp, pMat, fadePaint)
            else
              fadePaint.setAlpha(math.floor(255 * ((f - half + 1) / half)))
              local mat = Matrix()
              mat.postScale(scale, scale)
              mat.postTranslate(dx, dy)
              canvas.drawBitmap(cachedBmp, mat, fadePaint)
            end
          else
            local mat = Matrix()
            mat.postScale(scale, scale)
            mat.postTranslate(dx, dy)
            canvas.drawBitmap(cachedBmp, mat, imgPaint)
          end

          if drawSubs and subLayout then
            canvas.drawRect(0, subBoxTop, vidW, vidH, scrimPaint)
            canvas.save()
            local lh = subLayout.getHeight()
            local ty = vidH - lh - math.floor(vidH * 0.045)
            canvas.translate(math.floor(vidW * 0.06), ty)
            subLayout.draw(canvas)
            canvas.restore()
          end
          inputSurface.unlockCanvasAndPost(canvas)
        end
        drainVideoEncoder(false)
      end

      if prevBmp then
        pcall(function() prevBmp.recycle() end)
        prevBmp = nil
      end
    end

    if cachedBmp then pcall(function() cachedBmp.recycle() end) end
    if prevBmp then pcall(function() prevBmp.recycle() end) end

    drainVideoEncoder(true)
    pcall(function() vEncoder.stop() vEncoder.release() end)
    pcall(function() inputSurface.release() end)
    pcall(function() if vMuxStarted then vMuxer.stop() end vMuxer.release() end)

    setProgress("Finalizing MP4 video with audio...")
    local finalMp4 = cacheDir .. "/ai_video_" .. runId .. ".mp4"

    local vExt = MediaExtractor()
    vExt.setDataSource(tempVideoMp4)
    vExt.selectTrack(0)
    local vTrkFmt = vExt.getTrackFormat(0)

    local aExt = MediaExtractor()
    aExt.setDataSource(tempAudioM4a)
    aExt.selectTrack(0)
    local aTrkFmt = aExt.getTrackFormat(0)

    local finalMux = MediaMuxer(finalMp4, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    local outVIdx = finalMux.addTrack(vTrkFmt)
    local outAIdx = finalMux.addTrack(aTrkFmt)
    finalMux.start()

    local copyBuf = ByteBuffer.allocate(512 * 1024)
    local copyInfo = MediaCodec.BufferInfo()

    local function copyTrack(ext, dstIdx)
      while true do
        copyBuf.clear()
        local sz = ext.readSampleData(copyBuf, 0)
        if sz < 0 then break end
        copyInfo.offset = 0
        copyInfo.size = sz
        copyInfo.presentationTimeUs = ext.getSampleTime()
        copyInfo.flags = ext.getSampleFlags()
        finalMux.writeSampleData(dstIdx, copyBuf, copyInfo)
        ext.advance()
      end
    end

    copyTrack(vExt, outVIdx)
    copyTrack(aExt, outAIdx)

    pcall(function() finalMux.stop() finalMux.release() end)
    pcall(function() vExt.release() end)
    pcall(function() aExt.release() end)

    if not File(finalMp4).exists() or File(finalMp4).length() < 5000 then
      return false, "Final MP4 assembly failed."
    end
    return true, finalMp4, #visualGroups
  end, modeId, inputVal, fmt.w, fmt.h, sty.prompt, vce.id, transId, showSubs, CACHE_DIR, progressFile, function(ok, resOrErr, sceneCount)
    isGenerating = false
    btnGenerate.setEnabled(true)
    if statusTicker then
      pcall(function() statusTicker.stop() end)
      statusTicker = nil
    end
    pcall(function() progressDlg.dismiss() end)

    if ok then
      haptic(35)
      currentVideoPath = resOrErr
      currentVideoTitle = "AI_Video_" .. os.date("%Y%m%d_%H%M%S")
      sendReadyNotification(TOOL_TITLE, "Your full video (" .. tostring(sceneCount) .. " scenes) is ready!")
      if isHiddenInBackground then
        isHiddenInBackground = false
        bringAppToFront()
      end
      showVideoResultWindow(sceneCount)
    else
      haptic(35)
      sendReadyNotification(TOOL_TITLE, "Video generation failed: " .. tostring(resOrErr))
      if isHiddenInBackground then
        isHiddenInBackground = false
        bringAppToFront()
      end
      showErrorWindow(resOrErr)
    end
  end)
end

btnGenerate.setOnClickListener(View.OnClickListener{
  onClick = function()
    haptic(35)
    if isGenerating then
      Toast.makeText(activity, "Video generation is already running.", Toast.LENGTH_SHORT).show()
      return
    end
    if currentMode == "text" then
      local txt = etScript.getText().toString():gsub("^%s+", ""):gsub("%s+$", "")
      if txt == "" then
        Toast.makeText(activity, "Please enter your text first.", Toast.LENGTH_SHORT).show()
        return
      end
      startVideoGeneration("text", txt)
    else
      if not selectedAudioPath or not File(selectedAudioPath).exists() then
        Toast.makeText(activity, "Please select an audio file first.", Toast.LENGTH_SHORT).show()
        return
      end
      startVideoGeneration("audio", selectedAudioPath)
    end
  end
})

-- ==========================================
-- CLEAN & PROFESSIONAL ABOUT WINDOW
-- ==========================================
btnAbout.setOnClickListener(View.OnClickListener{
  onClick = function()
    haptic(35)
    local sv = ScrollView(activity)
    local dlgRoot = LinearLayout(activity)
    dlgRoot.setOrientation(LinearLayout.VERTICAL)
    dlgRoot.setPadding(dp(18), dp(18), dp(18), dp(18))
    dlgRoot.setBackground(makeGradBg("#1A0B2E", "#0B0714", 22, "#F59E0B", 2.0))
    sv.addView(dlgRoot)

    local function addAboutCard(head, body, startHex, endHex, borderHex, headHex)
      local c = LinearLayout(activity)
      c.setOrientation(LinearLayout.VERTICAL)
      c.setPadding(dp(15), dp(14), dp(15), dp(14))
      c.setBackground(makeGradBg(startHex, endHex, 15, borderHex, 1.4))
      local lp = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
      lp.bottomMargin = dp(11)

      local h = TextView(activity)
      h.setText(head)
      h.setTextColor(Color.parseColor(headHex or "#FFFFFF"))
      h.setTextSize(16)
      h.setTypeface(Typeface.DEFAULT_BOLD)
      setHeading(h)
      c.addView(h)

      local b = TextView(activity)
      b.setText(body)
      b.setTextColor(Color.parseColor("#F1F5F9"))
      b.setTextSize(13)
      b.setPadding(0, dp(6), 0, 0)
      b.setFocusable(true)
      c.addView(b)

      dlgRoot.addView(c, lp)
    end

    addAboutCard(TOOL_TITLE, DEV_NAME, "#3B0764", "#1E0736", "#F59E0B", "#FDE68A")

    addAboutCard(
      "Tool Overview",
      "AI Video Maker Studio creates complete narrated HD videos from either written text or your own audio recordings, with story-matched visual scenes, smooth transitions, and clear subtitles.",
      "#261806", "#140C03", "#F59E0B", "#FEF3C7"
    )

    addAboutCard(
      "Key Features",
      "• Text to Video Mode: Converts any Urdu or English story or script into a full narrated video.\n• Audio to Video Mode: Keeps your original audio file and automatically generates matching scenes and subtitles.\n• In-Tool Audio Browser: View total device audios, search live as you type, and preview with inline Play before selecting.\n• Smart Scene Switching: Detects changes in time, place, or mood and blends scenes smoothly.\n• Video Formats: Choose YouTube Landscape, Shorts and Reels, or Square video.\n• 6 Visual Styles and 3 Scene Transitions: Customize the look and feel of every video.\n• Background Mode: Tap HIDE while rendering to return to Home Screen with automatic reopen and notification when finished.\n• Built-in Player: Preview, rename, and save videos directly to Downloads.",
      "#06261E", "#041410", "#10B981", "#A7F3D0"
    )

    addAboutCard(
      "How to Use",
      "1. Choose Text to Video or Audio to Video from the Select Mode dropdown.\n2. Paste your script or pick an audio file using the in-tool Audio Browser.\n3. Select your Format, Visual Style, Voice, Transition, and Subtitles.\n4. Tap GENERATE FULL VIDEO and optionally tap HIDE to run in the background.\n5. Preview your finished video, rename if desired, and tap DOWNLOAD MP4.",
      "#2E0B1E", "#17050F", "#F43F5E", "#FECDD3"
    )

    local dlg = nil

    local btnFeedback = Button(activity)
    btnFeedback.setText("Send Feedback via WhatsApp")
    btnFeedback.setAllCaps(false)
    btnFeedback.setTextColor(Color.parseColor("#041A0E"))
    btnFeedback.setTextSize(15)
    btnFeedback.setTypeface(Typeface.DEFAULT_BOLD)
    btnFeedback.setPadding(dp(14), dp(13), dp(14), dp(13))
    btnFeedback.setBackground(makeGradBg("#25D366", "#16A34A", 14, "#86EFAC", 1.5))
    local lpFb = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
    lpFb.topMargin = dp(4)
    btnFeedback.setOnClickListener(View.OnClickListener{
      onClick = function()
        haptic(35)
        local msg = URLEncoder.encode("Assalam o Alaikum Abdul Rehman, I want to share feedback for AI Video Maker Studio: ", "UTF-8"):gsub("+", "%%20")
        local ok = pcall(function()
          local intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/" .. WHATSAPP_DIGITS .. "?text=" .. msg))
          activity.startActivity(intent)
        end)
        if not ok then
          Toast.makeText(activity, "WhatsApp: " .. WHATSAPP_NO, Toast.LENGTH_LONG).show()
        end
      end
    })
    dlgRoot.addView(btnFeedback, lpFb)

    local btnCloseAbout = Button(activity)
    btnCloseAbout.setText("CLOSE")
    btnCloseAbout.setAllCaps(false)
    btnCloseAbout.setTextColor(Color.parseColor("#F4F4F5"))
    btnCloseAbout.setTextSize(14)
    btnCloseAbout.setTypeface(Typeface.DEFAULT_BOLD)
    btnCloseAbout.setPadding(dp(12), dp(12), dp(12), dp(12))
    btnCloseAbout.setBackground(makeCardBg("#27272A", 14, "#52525B", 1.2))
    local lpCa = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
    lpCa.topMargin = dp(10)
    btnCloseAbout.setOnClickListener(View.OnClickListener{
      onClick = function()
        haptic(35)
        if dlg then dlg.dismiss() end
      end
    })
    dlgRoot.addView(btnCloseAbout, lpCa)

    dlg = showStyledDialog(sv)
  end
})

function onDestroy()
  haptic(35)
  stopPreviewPlayer()
  if welcomePlayer then
    pcall(function() welcomePlayer.stop() welcomePlayer.release() end)
  end
  if statusTicker then pcall(function() statusTicker.stop() end) end
end

pcall(function()
  Handler(Looper.getMainLooper()).postDelayed(Runnable{
    run = function()
      haptic(35)
      playWelcomeIntro(CACHE_DIR)
    end
  }, 150)
end)
