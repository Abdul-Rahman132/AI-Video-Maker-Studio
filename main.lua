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
import "org.json.*"

local TOOL_TITLE = "AI Video Maker Studio"
local DEV_NAME = "Developer: Abdul Rehman"
local WHATSAPP_NO = "+92 3124255300"
local WHATSAPP_DIGITS = "923124255300"
local GROQ_KEYS_URL = "https://console.groq.com/keys"

local CACHE_DIR = activity.getCacheDir().getAbsolutePath() .. "/ai_video_maker_cache"
local DOWNLOAD_DIR = "/storage/emulated/0/Download/AI_Video_Maker_Studio"
File(CACHE_DIR).mkdirs()

local prefs = activity.getSharedPreferences("ai_video_maker_prefs", Context.MODE_PRIVATE)
local groqApiKey = prefs.getString("groq_api_key", "") or ""

local currentMode = "text" -- "text" or "audio"
local selectedAudioPath = nil
local selectedAudioName = nil
local currentVideoPath = nil
local currentVideoTitle = "AI_Video_" .. os.date("%Y%m%d_%H%M%S")
local welcomePlayer = nil
local previewPlayer = nil
local isGenerating = false
local isHiddenInBackground = false
local isActivityPaused = false
local pendingOutcome = nil
local statusTicker = nil
local progressFile = CACHE_DIR .. "/progress_status.txt"
local cancelFlagFile = CACHE_DIR .. "/cancel_job.flag"

local FORMATS = {
  {label = "YouTube Landscape (1280x720)", w = 1280, h = 720},
  {label = "Shorts and Reels (720x1280)", w = 720, h = 1280},
  {label = "Square Video (720x720)", w = 720, h = 720}
}

local VISUAL_STYLES = {
  {label = "Cinematic Realistic", prompt = "cinematic photorealistic film still, natural realistic lighting matching the scene mood, ultra detailed, crisp 8k photography"},
  {label = "Dark Thriller Mystery", prompt = "cinematic noir thriller film still, moody atmospheric shadows, suspenseful cinema, ultra detailed"},
  {label = "3D Animation Style", prompt = "3d modern animated movie style, expressive visuals, vibrant cinematic lighting, ultra detailed"},
  {label = "Spiritual Scenic Art", prompt = "serene spiritual islamic art atmosphere, golden hour light, majestic peaceful scenery, respectful art"},
  {label = "Documentary Historical", prompt = "authentic documentary film still, realistic period details, natural cinematic lighting"},
  {label = "Anime Illustration", prompt = "high quality modern anime cinematic movie frame, vivid colors, dramatic storytelling art"}
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

local function deleteRecursive(fileObj)
  pcall(function()
    if not fileObj or not fileObj.exists() then return end
    if fileObj.isDirectory() then
      local children = fileObj.listFiles()
      if children then
        for i = 0, #children - 1 do
          deleteRecursive(children[i])
        end
      end
    end
    fileObj.delete()
  end)
end

local function cleanupOldCache(keepVideoPath)
  pcall(function()
    local dir = File(CACHE_DIR)
    local files = dir.listFiles()
    if not files then return end
    for i = 0, #files - 1 do
      local f = files[i]
      local nm = f.getName()
      local fp = f.getAbsolutePath()
      if f.isDirectory() and nm:find("^job_") then
        deleteRecursive(f)
      elseif nm:find("^ai_video_.*%.mp4$") and fp ~= keepVideoPath then
        f.delete()
      end
    end
  end)
end

cleanupOldCache(nil)

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

local function isActivityAlive()
  local alive = true
  pcall(function()
    if activity.isFinishing() then alive = false end
    if Build.VERSION.SDK_INT >= 17 and activity.isDestroyed() then alive = false end
  end)
  return alive
end

local function showStyledDialog(view)
  if not isActivityAlive() then return nil end
  local dlg = nil
  pcall(function()
    dlg = AlertDialog.Builder(activity).setView(view).create()
    if dlg.getWindow() then
      dlg.getWindow().setBackgroundDrawableResource(android.R.color.transparent)
    end
    dlg.show()
  end)
  return dlg
end

local function stopPreviewPlayer()
  if previewPlayer then
    pcall(function() previewPlayer.stop() end)
    pcall(function() previewPlayer.release() end)
    previewPlayer = nil
  end
end

local function makeSafeResumeIntent()
  local intent = nil
  pcall(function()
    local orig = activity.getIntent()
    if orig then
      intent = Intent(orig)
    end
  end)
  if not intent then
    pcall(function()
      intent = activity.getPackageManager().getLaunchIntentForPackage(activity.getPackageName())
    end)
  end
  if intent then
    intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP)
  end
  return intent
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
    local openIntent = makeSafeResumeIntent()
    local pi = nil
    if openIntent then
      local flags = PendingIntent.FLAG_UPDATE_CURRENT
      if Build.VERSION.SDK_INT >= 23 then
        flags = flags | PendingIntent.FLAG_IMMUTABLE
      end
      pi = PendingIntent.getActivity(activity, 902, openIntent, flags)
    end
    local builder = (Build.VERSION.SDK_INT >= 26)
      and Notification.Builder(activity, chanId)
      or  Notification.Builder(activity)
    builder.setContentTitle(titleText)
      .setContentText(bodyText)
      .setSmallIcon(android.R.drawable.ic_media_play)
      .setAutoCancel(true)
    if pi then builder.setContentIntent(pi) end
    nm.notify(902, builder.build())
  end)
end

local function bringAppToFront()
  if not isActivityAlive() then return end
  local moved = false
  pcall(function()
    local am = activity.getSystemService(Context.ACTIVITY_SERVICE)
    if am and activity.getTaskId then
      am.moveTaskToFront(activity.getTaskId(), 0)
      moved = true
    end
  end)
  if not moved then
    pcall(function()
      local orig = activity.getIntent()
      if orig and (orig.getData() ~= nil or orig.getExtras() ~= nil) then
        local resumeIntent = Intent(orig)
        resumeIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP)
        activity.startActivity(resumeIntent)
      end
    end)
  end
end

local function hideToHomeScreen()
  local hidden = false
  pcall(function()
    hidden = activity.moveTaskToBack(true)
  end)
  if not hidden then
    pcall(function()
      local home = Intent(Intent.ACTION_MAIN)
      home.addCategory(Intent.CATEGORY_HOME)
      home.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      activity.startActivity(home)
    end)
  end
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

-- Rich Cinematic Studio Startup Sound (Warm Bass Swell + Shimmering Maj9 Bell Arpeggio — Zero TTS!)
local function playWelcomeIntro(cachePath)
  task(function(outDir)
    require "import"
    import "java.io.*"

    local introPath = outDir .. "/video_maker_studio_intro_v5.wav"
    local chk = io.open(introPath, "rb")
    local hasIntro = false
    if chk then
      local sz = chk:seek("end")
      chk:close()
      if sz and sz > 20000 then hasIntro = true end
    end

    if not hasIntro then
      local sr = 22050
      local totalSec = 1.45
      local totalSamples = math.floor(sr * totalSec)
      local notes = {
        {f = 130.81, s = 0.00, a = 0.24, d = 1.5, h2 = 0.12, h3 = 0.04}, -- C3 warm bass swell
        {f = 196.00, s = 0.04, a = 0.16, d = 1.7, h2 = 0.10, h3 = 0.03}, -- G3 warm fifth
        {f = 261.63, s = 0.06, a = 0.22, d = 2.6, h2 = 0.18, h3 = 0.06}, -- C4
        {f = 329.63, s = 0.15, a = 0.20, d = 2.7, h2 = 0.18, h3 = 0.06}, -- E4
        {f = 392.00, s = 0.24, a = 0.20, d = 2.8, h2 = 0.18, h3 = 0.06}, -- G4
        {f = 493.88, s = 0.33, a = 0.19, d = 2.9, h2 = 0.16, h3 = 0.05}, -- B4
        {f = 587.33, s = 0.42, a = 0.18, d = 3.0, h2 = 0.15, h3 = 0.05}, -- D5
        {f = 783.99, s = 0.52, a = 0.17, d = 2.4, h2 = 0.14, h3 = 0.04}, -- G5 sparkle
        {f = 1046.50, s = 0.62, a = 0.14, d = 2.2, h2 = 0.10, h3 = 0.03} -- C6 shimmer tail
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
        for k = 1, #notes do
          local n = notes[k]
          if t >= n.s then
            local dt = t - n.s
            local att = (dt < 0.025) and (dt / 0.025) or 1.0
            local env = att * exp(-n.d * dt)
            local ph = twoPi * n.f * dt
            local tone = sin(ph) + n.h2 * sin(ph * 2.0) + n.h3 * sin(ph * 3.0)
            mix = mix + n.a * env * tone
          end
        end
        if t > 1.05 then
          local fade = (totalSec - t) / (totalSec - 1.05)
          if fade < 0 then fade = 0 end
          mix = mix * fade * fade
        end
        if mix > 0.90 then mix = 0.90 elseif mix < -0.90 then mix = -0.90 end
        local pcm = floor(mix * 30500)
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
      local f = io.open(introPath, "wb")
      if f then
        f:write(table.concat(chunks))
        f:close()
      end
    end

    return introPath
  end, cachePath, function(introPath)
    if introPath then
      playAudioFile(introPath, nil)
    end
  end)
end

-- ==========================================
-- GROQ API KEY WINDOW (Clean Sapphire Blue Theme)
-- ==========================================
local function showGroqKeyWindow(onUpdated)
  local wrap = LinearLayout(activity)
  wrap.setOrientation(LinearLayout.VERTICAL)
  wrap.setPadding(dp(18), dp(18), dp(18), dp(18))
  wrap.setBackground(makeGradBg("#0B1E3D", "#050D1E", 22, "#38BDF8", 2.0))

  local h = TextView(activity)
  h.setText("Groq API Key")
  h.setTextColor(Color.parseColor("#E0F2FE"))
  h.setTextSize(19)
  h.setTypeface(Typeface.DEFAULT_BOLD)
  setHeading(h)
  wrap.addView(h)

  local etKey = EditText(activity)
  etKey.setText(groqApiKey)
  etKey.setSingleLine(true)
  etKey.setHint("gsk_...")
  etKey.setHintTextColor(Color.parseColor("#64748B"))
  etKey.setTextColor(Color.parseColor("#FFFFFF"))
  etKey.setTextSize(14)
  etKey.setPadding(dp(14), dp(12), dp(14), dp(12))
  etKey.setBackground(makeCardBg("#040B14", 12, "#0284C7", 1.3))
  etKey.setContentDescription("Groq API key input")
  local lpEt = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpEt.topMargin = dp(12)
  wrap.addView(etKey, lpEt)

  local dlg = nil

  local bGet = Button(activity)
  bGet.setText("GET API KEY")
  bGet.setAllCaps(false)
  bGet.setTextColor(Color.parseColor("#03150E"))
  bGet.setTextSize(14)
  bGet.setTypeface(Typeface.DEFAULT_BOLD)
  bGet.setPadding(dp(12), dp(11), dp(12), dp(11))
  bGet.setBackground(makeGradBg("#10B981", "#059669", 12, "#A7F3D0", 1.3))
  local lpGet = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpGet.topMargin = dp(11)
  wrap.addView(bGet, lpGet)

  local actionRow = LinearLayout(activity)
  actionRow.setOrientation(LinearLayout.HORIZONTAL)
  local lpRow = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpRow.topMargin = dp(10)

  local bCancel = Button(activity)
  bCancel.setText("CANCEL")
  bCancel.setAllCaps(false)
  bCancel.setTextColor(Color.parseColor("#F4F4F5"))
  bCancel.setTextSize(14)
  bCancel.setTypeface(Typeface.DEFAULT_BOLD)
  bCancel.setPadding(dp(12), dp(11), dp(12), dp(11))
  bCancel.setBackground(makeGradBg("#27272A", "#18181B", 12, "#52525B", 1.2))
  local lpCan = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1)
  lpCan.rightMargin = dp(6)
  actionRow.addView(bCancel, lpCan)

  local bSave = Button(activity)
  bSave.setText("SAVE")
  bSave.setAllCaps(false)
  bSave.setTextColor(Color.parseColor("#FFFFFF"))
  bSave.setTextSize(14)
  bSave.setTypeface(Typeface.DEFAULT_BOLD)
  bSave.setPadding(dp(12), dp(11), dp(12), dp(11))
  bSave.setBackground(makeGradBg("#0284C7", "#0369A1", 12, "#7DD3FC", 1.3))
  local lpSv = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1)
  lpSv.leftMargin = dp(6)
  actionRow.addView(bSave, lpSv)

  wrap.addView(actionRow, lpRow)

  bGet.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      pcall(function()
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse(GROQ_KEYS_URL))
        activity.startActivity(intent)
      end)
    end
  })

  bCancel.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      if dlg then dlg.dismiss() end
    end
  })

  bSave.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      local k = etKey.getText().toString():gsub("%s+", "")
      groqApiKey = k
      prefs.edit().putString("groq_api_key", groqApiKey).putBoolean("first_setup_done", true).apply()
      if onUpdated then onUpdated() end
      Toast.makeText(activity, groqApiKey ~= "" and "Groq API key saved." or "Groq API key updated.", Toast.LENGTH_SHORT).show()
      if dlg then dlg.dismiss() end
    end
  })

  dlg = showStyledDialog(wrap)
end

-- ==========================================
-- FIRST-TIME WELCOME & SETUP DIALOG (Royal Indigo & Gold Theme)
-- ==========================================
local function showFirstTimeWelcomeDialog(onSetupDone)
  local wrap = LinearLayout(activity)
  wrap.setOrientation(LinearLayout.VERTICAL)
  wrap.setPadding(dp(20), dp(20), dp(20), dp(20))
  wrap.setBackground(makeGradBg("#1E1B4B", "#0D0B26", 24, "#FBBF24", 2.0))

  local heroBox = LinearLayout(activity)
  heroBox.setOrientation(LinearLayout.VERTICAL)
  heroBox.setPadding(dp(14), dp(12), dp(14), dp(12))
  heroBox.setBackground(makeGradBg("#312E81", "#1E1B4B", 15, "#FDE68A", 1.3))

  local h = TextView(activity)
  h.setText("Welcome to " .. TOOL_TITLE)
  h.setTextColor(Color.parseColor("#FFFFFF"))
  h.setTextSize(19)
  h.setTypeface(Typeface.DEFAULT_BOLD)
  setHeading(h)
  heroBox.addView(h)

  local d = TextView(activity)
  d.setText(DEV_NAME)
  d.setTextColor(Color.parseColor("#FDE68A"))
  d.setTextSize(13)
  d.setTypeface(Typeface.DEFAULT_BOLD)
  d.setPadding(0, dp(4), 0, 0)
  d.setFocusable(true)
  heroBox.addView(d)
  wrap.addView(heroBox)

  local note = TextView(activity)
  note.setText("Add your free Groq API Key once to unlock fast Audio-to-Video, synced Urdu subtitles, and consistent AI scenes.")
  note.setTextColor(Color.parseColor("#E0E7FF"))
  note.setTextSize(13)
  note.setPadding(dp(2), dp(12), dp(2), dp(10))
  note.setFocusable(true)
  wrap.addView(note)

  local etKey = EditText(activity)
  etKey.setText(groqApiKey)
  etKey.setSingleLine(true)
  etKey.setHint("gsk_...")
  etKey.setHintTextColor(Color.parseColor("#94A3B8"))
  etKey.setTextColor(Color.parseColor("#FFFFFF"))
  etKey.setTextSize(14)
  etKey.setPadding(dp(14), dp(12), dp(14), dp(12))
  etKey.setBackground(makeCardBg("#09071A", 12, "#818CF8", 1.3))
  etKey.setContentDescription("Groq API key input")
  wrap.addView(etKey)

  local bGet = Button(activity)
  bGet.setText("GET API KEY")
  bGet.setAllCaps(false)
  bGet.setTextColor(Color.parseColor("#03150E"))
  bGet.setTextSize(14)
  bGet.setTypeface(Typeface.DEFAULT_BOLD)
  bGet.setPadding(dp(12), dp(11), dp(12), dp(11))
  bGet.setBackground(makeGradBg("#34D399", "#059669", 12, "#A7F3D0", 1.3))
  local lpGet = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpGet.topMargin = dp(11)
  wrap.addView(bGet, lpGet)

  local row = LinearLayout(activity)
  row.setOrientation(LinearLayout.HORIZONTAL)
  local lpRow = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpRow.topMargin = dp(10)

  local bSkip = Button(activity)
  bSkip.setText("CANCEL")
  bSkip.setAllCaps(false)
  bSkip.setTextColor(Color.parseColor("#E2E8F0"))
  bSkip.setTextSize(14)
  bSkip.setTypeface(Typeface.DEFAULT_BOLD)
  bSkip.setPadding(dp(12), dp(11), dp(12), dp(11))
  bSkip.setBackground(makeGradBg("#27272A", "#18181B", 12, "#52525B", 1.2))
  local lpSk = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1)
  lpSk.rightMargin = dp(6)
  row.addView(bSkip, lpSk)

  local bSave = Button(activity)
  bSave.setText("SAVE")
  bSave.setAllCaps(false)
  bSave.setTextColor(Color.parseColor("#1C0F02"))
  bSave.setTextSize(14)
  bSave.setTypeface(Typeface.DEFAULT_BOLD)
  bSave.setPadding(dp(12), dp(11), dp(12), dp(11))
  bSave.setBackground(makeGradBg("#FBBF24", "#D97706", 12, "#FEF3C7", 1.3))
  local lpSv = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1)
  lpSv.leftMargin = dp(6)
  row.addView(bSave, lpSv)

  wrap.addView(row, lpRow)

  local dlg = AlertDialog.Builder(activity).setView(wrap).setCancelable(false).create()
  pcall(function()
    if dlg.getWindow() then
      dlg.getWindow().setBackgroundDrawableResource(android.R.color.transparent)
    end
  end)

  bGet.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      pcall(function()
        local intent = Intent(Intent.ACTION_VIEW, Uri.parse(GROQ_KEYS_URL))
        activity.startActivity(intent)
      end)
    end
  })

  bSkip.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      prefs.edit().putBoolean("welcome_setup_v1_done", true).apply()
      if dlg then dlg.dismiss() end
    end
  })

  bSave.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      local k = etKey.getText().toString():gsub("%s+", "")
      if k == "" then
        Toast.makeText(activity, "Please enter your Groq API key or tap CANCEL.", Toast.LENGTH_SHORT).show()
        return
      end
      groqApiKey = k
      prefs.edit().putString("groq_api_key", groqApiKey).putBoolean("welcome_setup_v1_done", true).apply()
      if onSetupDone then onSetupDone() end
      Toast.makeText(activity, "Groq API key saved. Welcome!", Toast.LENGTH_SHORT).show()
      if dlg then dlg.dismiss() end
    end
  })

  dlg.show()
end

-- ==========================================
-- IN-TOOL ACCESSIBLE AUDIO PICKER WINDOW
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
          if (low:find("%.mp3$") or low:find("%.wav$") or low:find("%.m4a$") or low:find("%.aac$") or low:find("%.ogg$") or low:find("%.opus$") or low:find("%.flac$")) and f.length() > 2000 then
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

  local allAudios = {}
  local isScanningAudios = true

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
  countTv.setText("Loading audio files...")
  countTv.setTextColor(Color.parseColor("#FDE68A"))
  countTv.setTextSize(13)
  countTv.setTypeface(Typeface.DEFAULT_BOLD)
  countTv.setPadding(0, dp(4), 0, 0)
  countTv.setFocusable(true)
  topCard.addView(countTv)

  wrap.addView(topCard)

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
  local searchHandler = Handler(Looper.getMainLooper())
  local searchRunnable = nil

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

    if isScanningAudios then
      countTv.setText("Loading audio files...")
      local loadTv = TextView(activity)
      loadTv.setText("Scanning your device audios...")
      loadTv.setTextColor(Color.parseColor("#CBD5E1"))
      loadTv.setTextSize(14)
      loadTv.setPadding(dp(8), dp(16), dp(8), dp(16))
      loadTv.setFocusable(true)
      listBox.addView(loadTv)
      return
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
        if searchRunnable then searchHandler.removeCallbacks(searchRunnable) end
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
      local qStr = tostring(s or "")
      if searchRunnable then searchHandler.removeCallbacks(searchRunnable) end
      searchRunnable = Runnable{
        run = function()
          renderList(qStr)
        end
      }
      searchHandler.postDelayed(searchRunnable, 250)
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
  task(function()
    require "import"
    import "android.provider.MediaStore"
    import "java.io.*"
    import "java.lang.*"
    import "org.json.*"
    local arr = JSONArray()
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
          if p and not seen[p] and File(p).exists() and File(p).length() > 2000 then
            seen[p] = true
            if not n or n == "" then n = File(p).getName() end
            local jo = JSONObject()
            jo.put("p", p)
            jo.put("n", n)
            jo.put("d", dur or 0)
            arr.put(jo)
          end
        end
        cursor.close()
      end
    end)
    if arr.length() == 0 then
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
            if (low:find("%.mp3$") or low:find("%.wav$") or low:find("%.m4a$") or low:find("%.aac$") or low:find("%.ogg$") or low:find("%.opus$") or low:find("%.flac$")) and f.length() > 2000 then
              local fp = f.getAbsolutePath()
              if not seen[fp] then
                seen[fp] = true
                local jo = JSONObject()
                jo.put("p", fp)
                jo.put("n", nm)
                jo.put("d", 0)
                arr.put(jo)
              end
            end
          end
        end
      end
      for _, dpPath in ipairs(dirs) do scanDir(dpPath, 0) end
    end
    return arr.toString()
  end, function(jsonStr)
    local parsed = {}
    pcall(function()
      if jsonStr and jsonStr ~= "" then
        local arr = JSONArray(jsonStr)
        for i = 0, arr.length() - 1 do
          local jo = arr.getJSONObject(i)
          parsed[#parsed + 1] = {
            path = jo.optString("p", ""),
            name = jo.optString("n", ""),
            durMs = jo.optLong("d", 0)
          }
        end
      end
    end)
    allAudios = parsed
    isScanningAudios = false
    if dlg and dlg.isShowing() then
      pcall(function() renderList(etSearch.getText().toString()) end)
    end
  end)
  if dlg then
    pcall(function()
      if dlg.getWindow() then
        dlg.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM)
      end
    end)
    dlg.setOnDismissListener(DialogInterface.OnDismissListener{
      onDismiss = function()
        if searchRunnable then searchHandler.removeCallbacks(searchRunnable) end
        stopPreviewPlayer()
      end
    })
  end
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

-- 3. Input Card (Espresso & Amber)
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
    b.setText((isSel and "Selected: " or "") .. itemLabel)
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

local btnFormat, btnStyle, btnVoice, btnTrans, btnSubs, btnGroqKey

local function getGroqBtnText()
  if groqApiKey ~= "" then
    return "Groq API Key: Connected"
  else
    return "Groq API Key: Not Set (Tap to Add)"
  end
end

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

btnGroqKey = makePickerBtn(getGroqBtnText(), "#0B2239", "#061321", "#38BDF8", function()
  showGroqKeyWindow(function()
    btnGroqKey.setText(getGroqBtnText())
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
-- RENAME WINDOW
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
-- SAVE MP4 HELPER (Scoped Storage Safe for Android 10-15+)
-- ==========================================
local function saveVideoToDownloads(srcPath, titleName)
  if not srcPath or not File(srcPath).exists() then
    return false, "Video file not found."
  end
  local fileName = titleName .. ".mp4"
  if Build.VERSION.SDK_INT >= 29 then
    local savedViaMediaStore = false
    pcall(function()
      local cr = activity.getContentResolver()
      local values = ContentValues()
      values.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
      values.put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
      values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS .. "/AI_Video_Maker_Studio")
      local itemUri = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
      if itemUri then
        local out = cr.openOutputStream(itemUri)
        local inp = FileInputStream(srcPath)
        local buf = byte[8192]
        local n = inp.read(buf)
        while n ~= -1 do
          out.write(buf, 0, n)
          n = inp.read(buf)
        end
        out.flush()
        out.close()
        inp.close()
        savedViaMediaStore = true
      end
    end)
    if savedViaMediaStore then
      return true, "Saved to Download/AI_Video_Maker_Studio/" .. fileName
    end
  end

  local ok = pcall(function()
    File(DOWNLOAD_DIR).mkdirs()
    local destPath = DOWNLOAD_DIR .. "/" .. fileName
    local inp = FileInputStream(srcPath)
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
    return true, "Saved to Download/AI_Video_Maker_Studio/" .. fileName
  end
  return false, "Could not save video. Check storage permission."
end

-- ==========================================
-- VIDEO READY & CINEMA PLAYER WINDOW
-- ==========================================
local function showVideoResultWindow(sceneCount)
  if not isActivityAlive() then return end
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
  hTv.setText("Video Ready")
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

  local btnPlayPause = makeResBtn("PLAY VIDEO", "#10B981", "#059669", "#A7F3D0", "#03150E")
  local btnDl        = makeResBtn("DOWNLOAD MP4", "#F59E0B", "#D97706", "#FDE68A", "#1C0F02")
  local btnRen       = makeResBtn("RENAME VIDEO", "#DB2777", "#9D174D", "#F9A8D4", "#FFFFFF")
  local btnClose     = makeResBtn("CLOSE", "#27272A", "#18181B", "#52525B", "#F4F4F5")

  local dlg = showStyledDialog(sv)

  vv.setVideoPath(currentVideoPath)
  vv.setOnPreparedListener(MediaPlayer.OnPreparedListener{
    onPrepared = function(mp)
      pcall(function() vv.seekTo(1) end)
    end
  })
  vv.setOnCompletionListener(MediaPlayer.OnCompletionListener{
    onCompletion = function()
      btnPlayPause.setText("PLAY AGAIN")
    end
  })

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

  local isSavingMp4 = false
  btnDl.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      if isSavingMp4 then return end
      isSavingMp4 = true
      btnDl.setEnabled(false)
      btnDl.setText("SAVING...")
      saveMsgTv.setText("Saving video to Downloads...")
      task(function(srcPath, titleName, dlDir)
        require "import"
        import "android.os.*"
        import "android.content.*"
        import "android.provider.MediaStore"
        import "android.media.MediaScannerConnection"
        import "java.io.*"
        import "java.lang.*"
        if not srcPath or not File(srcPath).exists() then
          return false, "Video file not found."
        end
        local fileName = titleName .. ".mp4"
        if Build.VERSION.SDK_INT >= 29 then
          local savedViaMediaStore = false
          pcall(function()
            local cv = ContentValues()
            cv.put("_display_name", fileName)
            cv.put("mime_type", "video/mp4")
            cv.put("relative_path", "Download/AI_Video_Maker_Studio")
            local resolver = activity.getContentResolver()
            local uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv)
            if uri then
              local out = resolver.openOutputStream(uri)
              local inp = FileInputStream(srcPath)
              local buf = byte[65536]
              local n = inp.read(buf)
              while n ~= -1 do
                out.write(buf, 0, n)
                n = inp.read(buf)
              end
              out.flush()
              out.close()
              inp.close()
              savedViaMediaStore = true
            end
          end)
          if savedViaMediaStore then
            return true, "Saved to Download/AI_Video_Maker_Studio/" .. fileName
          end
        end
        local ok = pcall(function()
          File(dlDir).mkdirs()
          local destPath = dlDir .. "/" .. fileName
          local inp = FileInputStream(srcPath)
          local out = FileOutputStream(destPath)
          local buf = byte[65536]
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
          return true, "Saved to Download/AI_Video_Maker_Studio/" .. fileName
        end
        return false, "Could not save video. Check storage permission."
      end, currentVideoPath, currentVideoTitle, DOWNLOAD_DIR, function(ok, msg)
        isSavingMp4 = false
        pcall(function()
          btnDl.setEnabled(true)
          btnDl.setText("DOWNLOAD MP4")
        end)
        if ok then
          pcall(function() saveMsgTv.setText(msg) end)
          Toast.makeText(activity, "Video saved to Downloads.", Toast.LENGTH_SHORT).show()
        else
          pcall(function() saveMsgTv.setText(msg) end)
          Toast.makeText(activity, msg, Toast.LENGTH_SHORT).show()
        end
      end)
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
      if dlg then dlg.dismiss() end
    end
  })
end

-- ==========================================
-- ERROR WINDOW
-- ==========================================
local function showErrorWindow(errText)
  if not isActivityAlive() then return end
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
-- DUAL-MODE FULL VIDEO GENERATOR WORKER (AUTO 2.5-MIN CHUNKING + AI SCENE DIRECTOR)
-- ==========================================
local function startVideoGeneration(modeId, inputVal)
  isGenerating = true
  isHiddenInBackground = false
  pendingOutcome = nil
  btnGenerate.setEnabled(false)
  pcall(function() File(cancelFlagFile).delete() end)
  cleanupOldCache(currentVideoPath)

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
  pNoteTv.setText("Tap HIDE to continue in background, or CANCEL to stop rendering.")
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
      Toast.makeText(activity, "Running in background. You will be notified when ready.", Toast.LENGTH_SHORT).show()
      hideToHomeScreen()
    end
  })
  pWrap.addView(btnHide, lpHide)

  local btnCancelGen = Button(activity)
  btnCancelGen.setText("CANCEL")
  btnCancelGen.setAllCaps(false)
  btnCancelGen.setTextColor(Color.parseColor("#FFFFFF"))
  btnCancelGen.setTextSize(14)
  btnCancelGen.setTypeface(Typeface.DEFAULT_BOLD)
  btnCancelGen.setPadding(dp(14), dp(12), dp(14), dp(12))
  btnCancelGen.setBackground(makeGradBg("#B91C1C", "#7F1D1D", 13, "#FCA5A5", 1.2))
  local lpCanGen = LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT)
  lpCanGen.topMargin = dp(9)
  btnCancelGen.setOnClickListener(View.OnClickListener{
    onClick = function()
      haptic(35)
      local cf = io.open(cancelFlagFile, "w")
      if cf then cf:write("1") cf:close() end
      btnCancelGen.setEnabled(false)
      btnCancelGen.setText("CANCELLING...")
      pStatusTv.setText("Stopping video generation...")
    end
  })
  pWrap.addView(btnCancelGen, lpCanGen)

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
        pcall(function() pStatusTv.setText(txt) end)
      end
    end
  end
  statusTicker.start()

  task(function(runMode, inputData, vidW, vidH, stylePrompt, voiceId, transMode, drawSubs, cacheDir, progPath, cancelPath, gKey)
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

    local function isCancelled()
      return File(cancelPath).exists()
    end

    local function sleepMs(ms)
      local step = 250
      local elapsed = 0
      while elapsed < ms do
        if isCancelled() then return end
        local d = math.min(step, ms - elapsed)
        pcall(function() Thread.sleep(d) end)
        elapsed = elapsed + d
      end
    end

    local function urlEncode(str)
      return URLEncoder.encode(str or "", "UTF-8"):gsub("+", "%%20")
    end

    local function getSafeAudioExt(pathStr)
      local ext = tostring(pathStr or ""):match("%.([%a%d]+)$")
      if ext then
        ext = string.lower(ext)
        if ext == "mp3" or ext == "wav" or ext == "m4a" or ext == "ogg" or ext == "flac" or ext == "webm" or ext == "mp4" or ext == "mpeg" or ext == "opus" then
          return ext
        end
      end
      return "mp3"
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

    local function sanitizeImagePrompt(promptText)
      local p = tostring(promptText or "")
      local banned = {
        "kissing", "kiss", "romance", "romantic", "intimate", "intimacy",
        "embrace", "embracing", "hugging", "hug", "nude", "nudity", "naked",
        "sensual", "seductive", "sexy", "couple", "lovers", "lips", "foreheads touching",
        "leaning close", "close faces", "medieval", "armor", "superhero", "cape"
      }
      for _, w in ipairs(banned) do
        p = p:gsub("%f[%a][Nn][Oo]%s+" .. w .. "%f[%A]", "")
        p = p:gsub("%f[%a]" .. w .. "%f[%A]", "")
        local cap = w:sub(1, 1):upper() .. w:sub(2)
        p = p:gsub("%f[%a]" .. cap .. "%f[%A]", "")
      end
      p = p:gsub("%s*,%s*,%s*", ", "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      return p
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
            if isCancelled() then break end
            out.write(buf, 0, n)
            totalRead = totalRead + n
            n = inp.read(buf)
          end
          out.flush()
          out.close()
          inp.close()
          if (not isCancelled()) and totalRead >= (minSize or 1500) and (expectedLen <= 0 or totalRead >= expectedLen) then
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

    -- Encode a byte slice of master_audio.pcm into a compact AAC .m4a chunk (~1.2 MB per 2.5 min)
    local function encodePcmSliceToM4a(pcmFilePath, startByte, sliceBytes, outM4aPath, sampleRate, channels)
      local okEnc = pcall(function()
        local aacFmt = MediaFormat.createAudioFormat("audio/mp4a-latm", sampleRate, channels)
        aacFmt.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
        aacFmt.setInteger(MediaFormat.KEY_BIT_RATE, 64000)
        aacFmt.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

        local enc = MediaCodec.createEncoderByType("audio/mp4a-latm")
        enc.configure(aacFmt, nil, nil, MediaCodec.CONFIGURE_FLAG_ENCODE)
        enc.start()

        local mux = MediaMuxer(outM4aPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        local trkIdx = -1
        local muxStarted = false

        local raf = RandomAccessFile(pcmFilePath, "r")
        raf.seek(startByte)
        local readBuf = byte[4096]
        local remaining = sliceBytes
        local fed = 0
        local bps = sampleRate * channels * 2
        local inDone = false
        local outDone = false
        local bInfo = MediaCodec.BufferInfo()

        while not outDone do
          if isCancelled() then break end
          if not inDone then
            local inIdx = enc.dequeueInputBuffer(10000)
            if inIdx >= 0 then
              local inBuf = enc.getInputBuffer(inIdx)
              inBuf.clear()
              if remaining <= 0 then
                local ptsUs = math.floor((fed / bps) * 1000000)
                enc.queueInputBuffer(inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                inDone = true
              else
                local toRead = math.min(4096, remaining)
                local n = raf.read(readBuf, 0, toRead)
                if n <= 0 then
                  local ptsUs = math.floor((fed / bps) * 1000000)
                  enc.queueInputBuffer(inIdx, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                  inDone = true
                else
                  inBuf.put(readBuf, 0, n)
                  local ptsUs = math.floor((fed / bps) * 1000000)
                  enc.queueInputBuffer(inIdx, 0, n, ptsUs, 0)
                  fed = fed + n
                  remaining = remaining - n
                end
              end
            end
          end

          local outIdx = enc.dequeueOutputBuffer(bInfo, 10000)
          if outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED then
            trkIdx = mux.addTrack(enc.getOutputFormat())
            mux.start()
            muxStarted = true
          elseif outIdx >= 0 then
            local outBuf = enc.getOutputBuffer(outIdx)
            if (bInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) ~= 0 then
              bInfo.size = 0
            end
            if bInfo.size > 0 and muxStarted then
              outBuf.position(bInfo.offset)
              outBuf.limit(bInfo.offset + bInfo.size)
              mux.writeSampleData(trkIdx, outBuf, bInfo)
            end
            enc.releaseOutputBuffer(outIdx, false)
            if (bInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) ~= 0 then
              outDone = true
            end
          end
        end

        pcall(function() raf.close() end)
        pcall(function() enc.stop() enc.release() end)
        pcall(function() if muxStarted then mux.stop() end mux.release() end)
      end)
      return okEnc and File(outM4aPath).exists() and File(outM4aPath).length() > 1000
    end

    -- 1. FAST & ACCURATE GROQ WHISPER TRANSCRIPTION (with optional UTF-8 prompt & forceLang)
    local function transcribeWithGroq(audioPath, apiKey, promptHint, forceLang)
      local fObj = File(audioPath)
      if fObj.length() > 24 * 1024 * 1024 then
        return nil, nil, "Audio chunk exceeded 24 MB.", nil
      end

      local safeName = "audio." .. getSafeAudioExt(audioPath)
      local boundary = "----GroqBoundary" .. tostring(os.time())
      local okReq, resText, resSegments, errMsg, detLang = pcall(function()
        local conn = URL("https://api.groq.com/openai/v1/audio/transcriptions").openConnection()
        conn.setRequestMethod("POST")
        conn.setConnectTimeout(20000)
        conn.setReadTimeout(120000)
        conn.setDoOutput(true)
        conn.setRequestProperty("Authorization", "Bearer " .. apiKey)
        conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" .. boundary)
        conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13)")

        local out = DataOutputStream(conn.getOutputStream())
        out.writeBytes("--" .. boundary .. "\r\n")
        out.writeBytes("Content-Disposition: form-data; name=\"file\"; filename=\"" .. safeName .. "\"\r\n")
        out.writeBytes("Content-Type: application/octet-stream\r\n\r\n")
        local fis = FileInputStream(audioPath)
        local buf = byte[8192]
        local n = fis.read(buf)
        while n ~= -1 do
          out.write(buf, 0, n)
          n = fis.read(buf)
        end
        fis.close()
        out.writeBytes("\r\n")

        out.writeBytes("--" .. boundary .. "\r\n")
        out.writeBytes("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        out.writeBytes("whisper-large-v3-turbo\r\n")

        out.writeBytes("--" .. boundary .. "\r\n")
        out.writeBytes("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        out.writeBytes("verbose_json\r\n")

        out.writeBytes("--" .. boundary .. "\r\n")
        out.writeBytes("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
        out.writeBytes("0\r\n")

        if forceLang and forceLang ~= "" then
          out.writeBytes("--" .. boundary .. "\r\n")
          out.writeBytes("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
          out.writeBytes(forceLang .. "\r\n")
        end

        if promptHint and promptHint ~= "" then
          out.writeBytes("--" .. boundary .. "\r\n")
          out.writeBytes("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
          out.write(String(promptHint).getBytes("UTF-8"))
          out.writeBytes("\r\n")
        end

        out.writeBytes("--" .. boundary .. "--\r\n")
        out.flush()
        out.close()

        local code = conn.getResponseCode()
        local stream = (code >= 200 and code < 300) and conn.getInputStream() or conn.getErrorStream()
        local sb = StringBuilder()
        if stream then
          local reader = BufferedReader(InputStreamReader(stream, "UTF-8"))
          local ln = reader.readLine()
          while ln ~= nil do sb.append(ln) ln = reader.readLine() end
          reader.close()
        end
        conn.disconnect()
        local raw = sb.toString()

        if code < 200 or code >= 300 then
          local gErr = "Groq HTTP " .. tostring(code)
          pcall(function()
            local jo = JSONObject(raw)
            if jo.has("error") then
              gErr = "Groq Error (" .. tostring(code) .. "): " .. jo.getJSONObject("error").optString("message", raw)
            end
          end)
          return nil, nil, gErr
        end

        local jo = JSONObject(raw)
        local fullText = jo.optString("text", "")
        local langStr = jo.optString("language", "")
        local segs = {}
        if jo.has("segments") then
          local sArr = jo.getJSONArray("segments")
          for i = 0, sArr.length() - 1 do
            local so = sArr.getJSONObject(i)
            local st = so.optDouble("start", 0.0)
            local en = so.optDouble("end", st + 2.0)
            local tx = cleanWhisperTranscript(so.optString("text", ""))
            if tx ~= "" then
              segs[#segs + 1] = {startSec = st, endSec = en, text = tx}
            end
          end
        end
        return fullText, segs, nil, langStr
      end)

      if not okReq then
        return nil, nil, "Groq connection failed: " .. tostring(resText), nil
      end
      return resText, resSegments, errMsg, detLang
    end

    -- 2. IMPROVED HUGGING FACE FALLBACK
    local function transcribeWithHuggingFace(audioPath)
      local spaces = {
        {base = "https://hf-audio-whisper-large-v3-turbo.hf.space", apiPrefix = "/gradio_api", endpoints = {"predict", "transcribe", "predict_1"}},
        {base = "https://hf-audio-whisper-large-v3.hf.space", apiPrefix = "/gradio_api", endpoints = {"predict", "transcribe", "predict_1"}},
        {base = "https://kingnish-realtime-whisper-large-v3-turbo.hf.space", apiPrefix = "/gradio_api", endpoints = {"predict", "transcribe"}},
        {base = "https://openai-whisper.hf.space", apiPrefix = "", endpoints = {"predict"}}
      }
      local safeName = "audio." .. getSafeAudioExt(audioPath)
      local lastErr = "No Hugging Face Whisper space responded."

      for _, sp in ipairs(spaces) do
        if isCancelled() then return nil, "Cancelled by user." end
        local okSp, transcript, spErr = pcall(function()
          local boundary = "----LuaBoundary" .. tostring(os.time())
          local uploadUrl = sp.base .. sp.apiPrefix .. "/upload"
          local conn = URL(uploadUrl).openConnection()
          conn.setRequestMethod("POST")
          conn.setConnectTimeout(20000)
          conn.setReadTimeout(90000)
          conn.setDoOutput(true)
          conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" .. boundary)
          conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 13)")

          local out = DataOutputStream(conn.getOutputStream())
          out.writeBytes("--" .. boundary .. "\r\n")
          out.writeBytes("Content-Disposition: form-data; name=\"files\"; filename=\"" .. safeName .. "\"\r\n")
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
          if uCode < 200 or uCode >= 300 then
            conn.disconnect()
            return nil, "Upload HTTP " .. tostring(uCode)
          end
          local reader = BufferedReader(InputStreamReader(conn.getInputStream(), "UTF-8"))
          local sb = StringBuilder()
          local ln = reader.readLine()
          while ln ~= nil do sb.append(ln) ln = reader.readLine() end
          reader.close()
          conn.disconnect()

          local upArr = JSONArray(sb.toString())
          if upArr.length() == 0 then return nil, "Empty upload response" end
          local remotePath = upArr.getString(0)

          local fileData = JSONObject()
          fileData.put("path", remotePath)
          fileData.put("orig_name", safeName)
          local meta = JSONObject()
          meta.put("_type", "gradio.FileData")
          fileData.put("meta", meta)

          local payloads = {}
          local arr2 = JSONArray()
          arr2.put(fileData)
          arr2.put("transcribe")
          payloads[1] = arr2
          local arr1 = JSONArray()
          arr1.put(fileData)
          payloads[2] = arr1

          local localErr = "Endpoint call failed"
          for _, ep in ipairs(sp.endpoints) do
            for _, dArr in ipairs(payloads) do
              local postObj = JSONObject()
              postObj.put("data", dArr)
              local callUrl = sp.base .. sp.apiPrefix .. "/call/" .. ep
              local pCode, pBody = httpRequest(callUrl, "POST", postObj.toString(), {["Content-Type"] = "application/json"}, 30000)
              if pCode >= 200 and pCode < 300 then
                local eid = JSONObject(pBody).optString("event_id", "")
                if eid ~= "" then
                  local sCode, sBody = httpRequest(callUrl .. "/" .. eid, "GET", nil, nil, 120000)
                  if sCode == 200 and sBody then
                    local lastEv = ""
                    for line in sBody:gmatch("[^\r\n]+") do
                      if line:find("^event:%s*") then
                        lastEv = line:match("^event:%s*(.+)")
                      elseif line:find("^data:%s*") then
                        local dpStr = line:match("^data:%s*(.+)")
                        if lastEv == "complete" then
                          local okJ, arr = pcall(function() return JSONArray(dpStr) end)
                          if okJ and arr then
                            for i = 0, arr.length() - 1 do
                              local v = arr.optString(i, "")
                              if v and #v > 3 and not v:find("^http") then
                                return v, nil
                              end
                            end
                          end
                        elseif lastEv == "error" then
                          localErr = "Server error: " .. tostring(dpStr)
                        end
                      end
                    end
                  end
                end
              else
                localErr = "HTTP " .. tostring(pCode)
              end
            end
          end
          return nil, localErr
        end)

        if okSp and transcript and #transcript > 3 then
          return transcript, nil
        elseif spErr then
          lastErr = tostring(spErr)
        end
      end
      return nil, lastErr
    end

    local function translateChunk(text, targetLang, srcLang)
      if not text or text == "" then return "" end
      local sl = srcLang or "auto"
      local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=" .. sl .. "&tl=" .. targetLang .. "&dt=t&q=" .. urlEncode(text)
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
        if okJ and translated and #translated > 1 then
          return translated:gsub("[\r\n\"]", " "):gsub("%s+", " ")
        end
      end
      return text
    end

    local groqChatComplete = nil
    local function fixCommonUrduMistakes(txt)
      if not txt or txt == "" or not hasUrduChars(txt) then return txt end
      local reps = {
        {"فیصلہ باد", "فیصل آباد"},
        {"فیصلہ بات", "فیصل آباد"},
        {"جمعہ تلسانی", "جمادی الثانی"},
        {"جمات الثانی", "جمادی الثانی"},
        {"جماد الثانی", "جمادی الثانی"},
        {"حجری", "ہجری"},
        {"سروج نکلنے", "سورج نکلنے"},
        {"سروج نکل کا", "سورج نکلنے کا"},
        {"سروج غروب", "سورج غروب"},
        {"سروج", "سورج"},
        {"درجہ ہرہ", "درجہ حرارت"},
        {"درجہ پر تیرہ", "درجہ حرارت تیرہ"},
        {"درجہ پر بارہ", "درجہ حرارت بارہ"},
        {"بکایا ہے", "بقایا ہیں"},
        {"پکایا ہے", "بقایا ہیں"},
        {"بکایا ہیں", "بقایا ہیں"},
        {"نیک ہوئی شاہد", "نیک خواہشات"},
        {"نئے خوانشات", "نیک خواہشات"},
        {"دعای صحت یعبی", "دعائے صحت یابی"},
        {"دعائی صحت یابی", "دعائے صحت یابی"},
        {"دعای مغفرت", "دعائے مغفرت"},
        {"دعائی مغفرت", "دعائے مغفرت"},
        {"تفعیق", "توفیق"},
        {"تفقیق", "توفیق"},
        {"اللہ نگے بان", "اللہ نگہبان"},
        {"اللہ نگہ بان", "اللہ نگہبان"},
        {"اللہ تکمان", "اللہ نگہبان"},
        {"کلنڈر", "کیلنڈر"},
        {"یوم میں پیدائش", "یومِ پیدائش"},
        {"یوم پیدائش", "یومِ پیدائش"},
        {"امران", "عمران"},
        {"شاہکل", "شاغل"},
        {"شاکل", "شاغل"},
        {"ساوپ دی", "سونپ دی"},
        {"Black Zero", "بلیک زیرو"},
        {"black zero", "بلیک زیرو"},
        {"Long Short Transfer System", "لانگ شارٹ ٹرانسفر سسٹم"},
        {"چھوتیس", "چھبیس"},
        {"چھو تیس", "چھبیس"},
        {"پچیسون", "پچیسواں"},
        {"چوبیسون", "چوبیسواں"},
        {"ستائیسون", "ستائیسواں"},
        {"اٹھائیسون", "اٹھائیسواں"},
        {"Yes boss", "یس بوس"},
        {"yes boss", "یس بوس"},
        {"Yes Boss", "یس بوس"},
        {"assistant", "اسسٹنٹ"},
        {"Assistant", "اسسٹنٹ"},
        {"گسیلے", "غصیلے"},
        {"لاٹل مرکھا", "لاعِلم رکھا"},
        {"الہدہ", "علیحدہ"},
        {"مسکریت ابھرانی", "مسکراہٹ ابھر آئی"},
        {"اپریشن", "آپریشن"},
        {"درجہ ہر ", "درجہ حرارت "},
        {"درجہ بر ", "درجہ حرارت "},
        {"ام اگر", "مگھر"},
        {"م اگر", "مگھر"},
        {"اللہ نیکے بان", "اللہ نگہبان"},
        {"اللہ نکے بان", "اللہ نگہبان"},
        {"سورج نیکل کا", "سورج نکلنے کا"},
        {"سورج نکل کا", "سورج نکلنے کا"},
        {"چوبیس ون", "چوبیسواں"},
        {"پچیس ون", "پچیسواں"}
      }
      for _, pair in ipairs(reps) do
        txt = txt:gsub(pair[1], pair[2])
      end
      return txt
    end

    local function ensureCleanUrdu(txt)
      if not txt or txt == "" then return "" end
      if hasDevanagariChars(txt) then
        local conv = nil
        if gKey and gKey ~= "" and groqChatComplete then
          conv = groqChatComplete(
            "Convert the given Hindi/Devanagari text strictly word-for-word into Pakistani Urdu Nastaliq script. Do NOT translate meanings or rephrase. Output ONLY the Urdu script text.",
            txt,
            gKey,
            180,
            0.0
          )
        end
        if (not conv) or #conv < 2 then
          conv = translateChunk(txt, "ur", "hi")
        end
        if conv and #conv > 1 then
          txt = cleanWhisperTranscript(conv)
        end
      end
      return fixCommonUrduMistakes(txt)
    end

    local function translateLongText(text, targetLang, srcLang)
      if #text <= 450 then
        return translateChunk(text, targetLang, srcLang)
      end
      local chunks = {}
      local buf = ""
      for word in text:gmatch("%S+") do
        if #buf + #word + 1 > 450 and buf ~= "" then
          chunks[#chunks + 1] = translateChunk(buf, targetLang, srcLang)
          buf = word
        else
          buf = (buf == "" and word or (buf .. " " .. word))
        end
      end
      if buf ~= "" then
        chunks[#chunks + 1] = translateChunk(buf, targetLang, srcLang)
      end
      return table.concat(chunks, " ")
    end

    local function translateToEnglish(text)
      if not hasNonAsciiChars(text) then return text end
      return translateChunk(text, "en", "auto")
    end

    -- 3. SMART UNIVERSAL AI SCENE DIRECTOR & URDU SUBTITLE PROOFREADER VIA GROQ LLM
    local activeGroqChatModel = nil
    local groqChatModels = {"llama-3.3-70b-versatile", "openai/gpt-oss-120b", "openai/gpt-oss-20b", "llama-3.1-8b-instant"}

    groqChatComplete = function(sysPrompt, usrPrompt, apiKey, maxTokens, temp)
      if not apiKey or apiKey == "" then return nil end
      -- Build failover order starting with activeGroqChatModel, then all remaining models (never stuck on 429!)
      local modelsToTry = {}
      if activeGroqChatModel then modelsToTry[#modelsToTry + 1] = activeGroqChatModel end
      for _, m in ipairs(groqChatModels) do
        if m ~= activeGroqChatModel then modelsToTry[#modelsToTry + 1] = m end
      end

      for _, mdl in ipairs(modelsToTry) do
        if isCancelled() then return nil end
        local okReq, resultTxt, wasRateLimited = pcall(function()
          local reqObj = JSONObject()
          reqObj.put("model", mdl)
          reqObj.put("temperature", temp or 0.2)
          reqObj.put("max_tokens", maxTokens or 90)

          local msgs = JSONArray()
          local m1 = JSONObject()
          m1.put("role", "system")
          m1.put("content", sysPrompt)
          msgs.put(m1)

          local m2 = JSONObject()
          m2.put("role", "user")
          m2.put("content", usrPrompt)
          msgs.put(m2)

          reqObj.put("messages", msgs)

          local code, body = httpRequest(
            "https://api.groq.com/openai/v1/chat/completions",
            "POST",
            reqObj.toString(),
            {
              ["Authorization"] = "Bearer " .. apiKey,
              ["Content-Type"] = "application/json"
            },
            25000
          )
          if code == 429 then
            return nil, true
          end
          if code >= 200 and code < 300 and body and body ~= "" then
            local jo = JSONObject(body)
            local ch = jo.getJSONArray("choices")
            if ch.length() > 0 then
              local txt = ch.getJSONObject(0).getJSONObject("message").optString("content", "")
              if txt and #txt >= 4 then
                return txt, false
              end
            end
          end
          return nil, false
        end)
        if okReq and resultTxt and #resultTxt >= 4 then
          activeGroqChatModel = mdl
          return resultTxt
        end
        if wasRateLimited then
          activeGroqChatModel = nil
          sleepMs(1000)
        end
      end
      return nil
    end

    -- Proofread Whisper Urdu segments in batches to fix common speech-to-text spelling slips
    local function proofreadUrduSegmentsWithGroq(segs, apiKey)
      if (not apiKey) or apiKey == "" or (not segs) or (#segs == 0) then return end
      local sampleTxt = ""
      for i = 1, math.min(#segs, 8) do sampleTxt = sampleTxt .. " " .. (segs[i].text or "") end
      if not hasUrduChars(sampleTxt) then return end

      for i = 1, #segs do
        segs[i].text = fixCommonUrduMistakes(segs[i].text or "")
      end

      local batchSize = 12
      local sysPrompt = "You are a strict, perfectionist Pakistani Urdu Nastaliq subtitle editor performing a final quality audit. Read the full context of all lines first, verify every word, and fix EVERY phonetic Whisper spelling error, garbled Urdu number (e.g. چھوتیس -> چھبیس), broken date/month/city/character name, or wrong Urdu phrase (e.g. فیصل آباد، جمادی الثانی، ہجری، بکرمی دیسی مہینے جیسے چیت، بیساکھ، جیٹھ، ہاڑھ، ساون، بھادوں، اسوج، کتک، مگھر، پوہ، ماگھ، پھاگن — never put an English month like اگست before بکرمی, سورج نکلنے، درجہ حرارت، بقایا ہیں، نیک خواہشات، دعائے صحت یابی، دعائے مغفرت، توفیق عطا فرمائے، اللہ نگہبان، دانش منزل، عمران، شاغل، ناٹران، وادی وارنگ). Rules: 1) Output ONLY pure Urdu Nastaliq script — transliterate English words or names inside Urdu lines into Urdu script (e.g. Black Zero -> بلیک زیرو, SSM -> ایس ایس ایم). 2) Zero Hindi/Devanagari or commentary. 3) Keep the EXACT same line numbers and 'N|corrected text' format. 4) Never merge, skip, add, or alter the true spoken meaning."

      local idx = 1
      while idx <= #segs do
        if isCancelled() then return end
        local endIdx = math.min(#segs, idx + batchSize - 1)
        local linesIn = {}
        for i = idx, endIdx do
          linesIn[#linesIn + 1] = tostring(i) .. "|" .. (segs[i].text or "")
        end
        local resp = groqChatComplete(sysPrompt, table.concat(linesIn, "\n"), apiKey, 1400, 0.0)
        if resp then
          for ln in resp:gmatch("[^\r\n]+") do
            local numStr, fixedTxt = ln:match("^%s*(%d+)%s*|%s*(.+)$")
            if numStr and fixedTxt then
              local n = tonumber(numStr)
              if n and n >= idx and n <= endIdx then
                fixedTxt = fixCommonUrduMistakes(cleanWhisperTranscript(fixedTxt))
                local origLen = math.max(1, #(segs[n].text or ""))
                if #fixedTxt >= math.max(2, math.floor(origLen * 0.35)) and #fixedTxt <= math.max(45, math.floor(origLen * 2.3)) then
                  segs[n].text = fixedTxt
                end
              end
            end
          end
        end
        idx = endIdx + 1
      end
    end

    local function hasExplicitFemaleCue(txt)
      local low = string.lower(txt or "")
      local cues = {
        "لڑکی", "عورت", "خاتون", "خواتین", "ماں", "والدہ", "بہن", "بیوی", "بیٹی", "دلہن", "بچی",
        "woman", "girl", "lady", "female", "mother", "sister", "wife", "daughter", "actress", "queen", "princess"
      }
      for _, c in ipairs(cues) do
        if low:find(c, 1, true) then return true end
      end
      return false
    end

    local function enforceCharacterGender(promptText, spokenText)
      if not promptText or promptText == "" then return promptText end
      if hasExplicitFemaleCue(spokenText) then return promptText end
      local p = promptText
      p = p:gsub("%f[%a][Bb]usinesswoman%f[%A]", "short-haired South Asian man")
      p = p:gsub("%f[%a][Yy]oung%s+[Ww]oman%f[%A]", "short-haired South Asian man")
      p = p:gsub("%f[%a][Ww]oman%f[%A]", "short-haired South Asian man")
      p = p:gsub("%f[%a][Ww]omen%f[%A]", "short-haired South Asian men")
      p = p:gsub("%f[%a][Gg]irl%f[%A]", "short-haired South Asian man")
      p = p:gsub("%f[%a][Gg]irls%f[%A]", "short-haired South Asian men")
      p = p:gsub("%f[%a][Ff]emale%f[%A]", "male")
      p = p:gsub("%f[%a][Ll]ady%f[%A]", "short-haired South Asian man")
      p = p:gsub("%f[%a][Ss]ecretary%f[%A]", "male assistant")
      p = p:gsub("%f[%a][Aa]%s+[Pp]erson%f[%A]", "a short-haired South Asian man")
      p = p:gsub("%f[%a][Tt]wo%s+[Cc]olleagues%f[%A]", "two short-haired South Asian men")
      p = p:gsub("%f[%a][Tt]wo%s+[Pp]eople%f[%A]", "two short-haired South Asian men")
      p = p:gsub("%f[%a][Aa]n%s+[Aa]gent%f[%A]", "a short-haired South Asian male agent")
      p = p:gsub("%f[%a][Aa]n%s+[Aa]ssistant%f[%A]", "a short-haired South Asian male assistant")
      p = p:gsub("%f[%a][Aa]n%s+[Oo]fficer%f[%A]", "a short-haired South Asian male officer")
      p = p:gsub("%f[%a][Ss]he%f[%A]", "he")
      p = p:gsub("%f[%a][Hh]er%f[%A]", "his")
      return p
    end

    -- Build a fixed Character Casting Sheet once per story so recurring characters keep the exact same face, hair, age & outfit across all scenes!
    local function buildCharacterBibleWithGroq(storyOverview, apiKey)
      if (not apiKey) or apiKey == "" or (not storyOverview) or #storyOverview < 30 then return "" end
      local sysPrompt = "You are a film casting director. Read this audio overview. If it is a story or dialogue with recurring named characters (e.g. Imran, Shagil, Naghar, Natran, Ali, Sara), list up to 4 main characters with ONE fixed, ultra-specific realistic visual appearance each (exact gender, age, ethnicity/South Asian for Urdu, hairstyle, facial hair, and clothing) so the SAME character looks identical in every scene. Format: 'Name: exact visual look.' on separate lines. If this audio is NOT a character story (e.g. daily calendar, weather, Islamic greeting, nature, general lecture), reply ONLY with NONE."
      local res = groqChatComplete(sysPrompt, storyOverview, apiKey, 240, 0.1)
      if res then
        local trimmed = res:gsub("^%s+", ""):gsub("%s+$", "")
        if string.upper(trimmed) == "NONE" or #trimmed < 12 then return "" end
        return trimmed
      end
      return ""
    end

    local function directSceneWithGroq(storyOverview, characterBible, prevSceneDesc, sceneText, apiKey)
      if not apiKey or apiKey == "" then return nil end

      local sysPrompt = "You are a strict, disciplined cinema storyboard director. First lock the overall visual mood to the Overall audio topic: if the audio is a peaceful Islamic, Jummah, daily calendar, sunrise/sunset, weather, or prayer message, EVERY single scene MUST stay bright, serene, sunlit, and uplifting (sky, sunrise, clouds, Pakistani city skyline, desk calendar, sunlit flowers, golden mosque domes — NEVER dark corridors, shadowy figures, or thriller rooms). If the narration mentions temperature, weather, or forecast (درجہ حرارت، موسم، امکان), ALWAYS depict a bright clear blue sky with soft clouds and warm sunlight over a city. CHARACTER CONSISTENCY RULE: If a Character Casting Sheet is provided and a named character appears right now, COPY their EXACT locked age, hairstyle, facial hair, and outfit verbatim so they look like the SAME actor throughout the entire video, while changing ONLY their facial expression (smiling, tense, angry, surprised, calm), pose, camera angle, and setting to match the current dialogue. STRICT GENDER RULE: NEVER use gender-neutral nouns like 'person', 'agent', or 'operator' alone — ALWAYS explicitly specify 'a short-haired South Asian man' or 'two short-haired South Asian men' unless the spoken text explicitly names a woman, girl, mother, sister, or wife. Use natural human eyes, sharp clear faces, keep multiple people respectfully spaced apart, vary camera angles from the previous scene, and write ONE concrete positive family-friendly English visual description (22-35 words)."
      local prevLine = (prevSceneDesc and prevSceneDesc ~= "") and ("Previous scene: " .. prevSceneDesc) or "Previous scene: Opening scene"
      local castLine = (characterBible and characterBible ~= "") and ("Character Casting Sheet (keep identical look):\n" .. characterBible .. "\n") or ""
      local usrPrompt = "Overall audio topic: " .. storyOverview .. "\n" .. castLine .. prevLine .. "\nSpoken narration right now: " .. sceneText
      local txt = groqChatComplete(sysPrompt, usrPrompt, apiKey, 95, 0.25)
      if txt then
        txt = txt:gsub("[\r\n\"]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        txt = enforceCharacterGender(sanitizeImagePrompt(txt), sceneText)
        if #txt >= 12 then
          return txt
        end
      end
      return nil
    end

    local function detectSituationTag(txt)
      local low = string.lower(txt or "")
      if low:find("جمعہ") or low:find("مبارک") or low:find("مسجد") or low:find("اللہ") or low:find("دعا") or low:find("قرآن") or low:find("نماز") or low:find("توفیق") or low:find("jummah") or low:find("mosque") or low:find("prayer") or low:find("quran") then return "islamic" end
      if low:find("سورج") or low:find("طلوع") or low:find("غروب") or low:find("صبح") or low:find("دھوپ") or low:find("sunrise") or low:find("sunset") or low:find("morning") then return "sunrise" end
      if low:find("درجہ") or low:find("حرارت") or low:find("موسم") or low:find("گرمی") or low:find("سردی") or low:find("بادل") or low:find("weather") or low:find("temperature") or low:find("forecast") then return "weather" end
      if low:find("کیلنڈر") or low:find("تاریخ") or low:find("ہجری") or low:find("بکرمی") or low:find("عیسوی") or low:find("نومبر") or low:find("دسمبر") or low:find("جنوری") or low:find("ہفتے") or low:find("calendar") or low:find("date") then return "calendar" end
      if low:find("ہسپتال") or low:find("بیمار") or low:find("صحت") or low:find("ڈاکٹر") or low:find("مریض") or low:find("hospital") or low:find("health") or low:find("doctor") then return "hospital" end
      if low:find("پیدائش") or low:find("سالگرہ") or low:find("خواہشات") or low:find("مبارکباد") or low:find("birthday") or low:find("celebration") then return "birthday" end
      if low:find("پردہ فرما") or low:find("مغفرت") or low:find("وفات") or low:find("مرحوم") or low:find("دنیا فانی") or low:find("memorial") then return "memorial" end
      if low:find("فون") or low:find("ٹیلی فون") or low:find("ریسیور") or low:find("ڈائل") or low:find("کال") or low:find("phone") or low:find("receiver") or low:find("call") then return "phone" end
      if low:find("دفتر") or low:find("فائل") or low:find("میز") or low:find("کرسی") or low:find("باس") or low:find("بوس") or low:find("اسسٹنٹ") or low:find("چیف") or low:find("وزیراعظم") or low:find("office") or low:find("desk") or low:find("file") or low:find("boss") or low:find("chief") then return "office" end
      if low:find("وادی") or low:find("پروجیکٹ") or low:find("سرحد") or low:find("خفیہ") or low:find("سیکرٹ") or low:find("valley") or low:find("project") or low:find("border") or low:find("secret") then return "secret_base" end
      if low:find("پولیس") or low:find("ایمبولینس") or low:find("سائرن") or low:find("police") or low:find("ambulance") or low:find("siren") then return "emergency" end
      if low:find("آگ") or low:find("دھماک") or low:find("شعلے") or low:find("fire") or low:find("explosion") then return "fire" end
      if low:find("بارش") or low:find("بجلی") or low:find("طوفان") or low:find("rain") or low:find("storm") then return "storm" end
      if low:find("درواز") or low:find("دستک") or low:find("داخل") or low:find("door") or low:find("knock") then return "door" end
      if low:find("سڑک") or low:find("گاڑی") or low:find("پہاڑ") or low:find("road") or low:find("car") or low:find("mountain") then return "road" end
      if low:find("تہہ خان") or low:find("گودام") or low:find("قید") or low:find("basement") or low:find("warehouse") then return "basement" end
      if low:find("پستول") or low:find("گولی") or low:find("تھپڑ") or low:find("مکا") or low:find("gun") or low:find("pistol") or low:find("fight") then return "action" end
      return "general"
    end

    local SITUATION_ANCHORS = {
      islamic = "Majestic peaceful mosque domes bathed in warm golden Friday morning sunlight, serene sky, calm uplifting atmosphere",
      sunrise = "Breathtaking golden sunrise and glowing orange sky over a peaceful modern Pakistani city skyline and green trees",
      weather = "Wide bright scenic view of clear blue sky with soft white clouds and warm sunlight over a clean modern city",
      calendar = "Warm sunlit wooden desk by a bright window with a neat desk calendar, notebook, pen, and cup of tea in soft morning light",
      hospital = "Peaceful sunlit modern hospital window with warm morning rays and fresh white flowers on a bedside table, hopeful atmosphere",
      birthday = "Warm cheerful celebration table with soft glowing golden candles, fresh flowers, and festive warm bokeh lights",
      memorial = "Serene peaceful twilight sky with soft golden clouds and gentle rays of light over tranquil nature, reflective mood",
      phone = "Medium shot of a person in modern attire seated at a wooden office desk holding a classic landline telephone receiver",
      office = "Medium shot inside a modern office with wooden desk, paper files, and two colleagues seated respectfully across the desk",
      secret_base = "Wide cinematic aerial shot of a hidden modern high-security concrete facility inside a misty mountain valley at dusk",
      door = "Medium shot inside a modern room as a person enters through a wooden door carrying paper folders",
      emergency = "Modern city street at night with police cars and flashing blue emergency lights",
      fire = "Dramatic modern realistic fire and smoke rising from an industrial building at night",
      storm = "Dark dramatic rainstorm and lightning over wet modern city streets at night",
      road = "Modern car driving along a scenic misty highway at dusk",
      basement = "Dimly lit concrete underground room with overhead lamp light and empty chairs",
      action = "Tense modern thriller confrontation in a dramatic corridor, characters standing apart in suspense",
      general = "Cinematic photorealistic wide scenic view matching the exact narration topic and mood, natural lighting, crisp details"
    }

    local function splitIntoLines(txt, isWideScript)
      local maxChunkBytes = isWideScript and 115 or 72
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
      -- Merge tiny 1-word orphan lines (e.g. lone "ہے") into the previous line
      local merged = {}
      for _, ln in ipairs(lines) do
        local wordCount = 0
        for _ in ln:gmatch("%S+") do wordCount = wordCount + 1 end
        if #merged > 0 and wordCount <= 1 and #ln <= 14 and (#merged[#merged] + #ln + 1) <= (maxChunkBytes + 20) then
          merged[#merged] = merged[#merged] .. " " .. ln
        else
          merged[#merged + 1] = ln
        end
      end
      return merged
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
        if isCancelled() then break end
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

      if (not isCancelled()) and addPauseSec and addPauseSec > 0 then
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

      local lockedProvider = nil
      local function fetchLineVoice(text, outMp3)
        local enc = urlEncode(text)
        if activeVoice == "ur" then
          return downloadBinary("https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=ur&q=" .. enc, outMp3, 25000, 800)
        end
        if lockedProvider == "gtts" then
          return downloadBinary("https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en-US&q=" .. enc, outMp3, 25000, 800)
        end
        local ok = downloadBinary("https://api.streamelements.com/kappa/v2/speech?voice=" .. activeVoice .. "&text=" .. enc, outMp3, 25000, 800)
        if ok then
          lockedProvider = "se"
          return true
        end
        if lockedProvider == nil then
          ok = downloadBinary("https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=en-US&q=" .. enc, outMp3, 25000, 800)
          if ok then lockedProvider = "gtts" end
          return ok
        end
        return false
      end

      for i, sText in ipairs(lines) do
        if isCancelled() then pcmOut.close() return false, "Cancelled by user." end
        setProgress(string.format("Recording Voice %d of %d...", i, #lines))
        local mp3Path = workDir .. "/voice_" .. i .. ".mp3"
        local vOk = fetchLineVoice(sText, mp3Path)
        if not vOk and not isCancelled() then
          sleepMs(1500)
          vOk = fetchLineVoice(sText, mp3Path)
        end
        if isCancelled() then pcmOut.close() return false, "Cancelled by user." end
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
      pcmOut.flush()
      pcmOut.close()
    else
      setProgress("Analyzing your selected audio...")
      local pcmBytes = decodeAudioToPcm(inputData, 0)
      pcmOut.flush()
      pcmOut.close()

      if isCancelled() then return false, "Cancelled by user." end
      local bytesPerSec = audioSampleRate * audioChannels * 2
      local totalAudioSec = pcmBytes / math.max(1, bytesPerSec)
      if totalAudioSec < 1.0 then
        return false, "Could not decode the selected audio file."
      end

      -- AUTO 50-SECOND CHUNKING + NATIVE URDU LOCK + GAP RECOVERY (Zero 30-70s drops, unlimited audio length)
      local CHUNK_SEC = 50
      local frameAlign = audioChannels * 2
      local useChunking = (totalAudioSec > 55.0) or (File(inputData).length() > 18 * 1024 * 1024)

      local allTimedSegments = {}
      local allRawParts = {}
      local errDetail = nil
      local lockedWhisperLang = nil

      local function transcribeFileSmart(filePath, hintTxt)
        local rTxt, rSegs, rErr, dLang = transcribeWithGroq(filePath, gKey, hintTxt, lockedWhisperLang)
        if (not rSegs or #rSegs == 0) and (not rTxt or #rTxt < 2) and not isCancelled() then
          sleepMs(1800)
          rTxt, rSegs, rErr, dLang = transcribeWithGroq(filePath, gKey, hintTxt, lockedWhisperLang)
        end
        -- If Whisper returned Hindi/Devanagari for Urdu speech, lock language="ur" and re-transcribe natively in Urdu!
        local lowLang = string.lower(dLang or "")
        local checkSample = (rTxt or "")
        if checkSample == "" and rSegs and #rSegs > 0 then checkSample = rSegs[1].text or "" end
        if (lockedWhisperLang == nil) and (lowLang == "hindi" or hasDevanagariChars(checkSample)) then
          lockedWhisperLang = "ur"
          local uTxt, uSegs, uErr = transcribeWithGroq(filePath, gKey, nil, "ur")
          if (uSegs and #uSegs > 0) or (uTxt and #uTxt > 2) then
            rTxt, rSegs, rErr = uTxt, uSegs, uErr
          end
        elseif lockedWhisperLang == nil then
          if lowLang == "urdu" or hasUrduChars(checkSample) then
            lockedWhisperLang = "ur"
          elseif lowLang == "english" then
            lockedWhisperLang = "en"
          end
        end
        return rTxt, rSegs, rErr
      end

      local function encodeAndTranscribeWindow(winStart, winDur, tagName, hintTxt)
        local startByte = math.floor(winStart * bytesPerSec)
        startByte = startByte - (startByte % frameAlign)
        local sliceBytes = math.floor(winDur * bytesPerSec)
        sliceBytes = sliceBytes - (sliceBytes % frameAlign)
        if startByte + sliceBytes > pcmBytes then
          sliceBytes = pcmBytes - startByte
          sliceBytes = sliceBytes - (sliceBytes % frameAlign)
        end
        if sliceBytes <= bytesPerSec * 0.5 then return nil, nil, nil end
        local chunkM4a = workDir .. "/chunk_" .. tagName .. ".m4a"
        local encOk = encodePcmSliceToM4a(pcmPath, startByte, sliceBytes, chunkM4a, audioSampleRate, audioChannels)
        if isCancelled() or not encOk then
          pcall(function() File(chunkM4a).delete() end)
          return nil, nil, nil
        end
        local rTxt, rSegs, rErr = transcribeFileSmart(chunkM4a, hintTxt)
        pcall(function() File(chunkM4a).delete() end)
        return rTxt, rSegs, rErr
      end

      if gKey and gKey ~= "" then
        if not useChunking then
          setProgress("Transcribing audio via Groq Whisper AI...")
          local rTxt, rSegs, rErr = transcribeFileSmart(inputData, nil)
          errDetail = rErr
          if rSegs and #rSegs > 0 then
            for _, sg in ipairs(rSegs) do allTimedSegments[#allTimedSegments + 1] = sg end
          elseif rTxt and #rTxt > 2 then
            allRawParts[#allRawParts + 1] = rTxt
          end
        else
          local numChunks = math.ceil(totalAudioSec / CHUNK_SEC)
          local prevPromptHint = ""
          for cIdx = 1, numChunks do
            if isCancelled() then return false, "Cancelled by user." end
            setProgress(string.format("Transcribing Part %d of %d via Groq AI...", cIdx, numChunks))

            local startSec = (cIdx - 1) * CHUNK_SEC
            local chunkDur = math.min(CHUNK_SEC, totalAudioSec - startSec)
            local rTxt, rSegs, rErr = encodeAndTranscribeWindow(startSec, chunkDur, tostring(cIdx), prevPromptHint)

            if rErr and #allTimedSegments == 0 and #allRawParts == 0 then
              errDetail = rErr
            end

            local chunkSegs = {}
            if rSegs and #rSegs > 0 then
              for _, sg in ipairs(rSegs) do
                local adjStart = startSec + sg.startSec
                local adjEnd = math.min(startSec + chunkDur, startSec + sg.endSec)
                if adjEnd > adjStart + 0.1 then
                  chunkSegs[#chunkSegs + 1] = {
                    startSec = adjStart,
                    endSec = adjEnd,
                    text = sg.text
                  }
                end
              end
            elseif rTxt and #rTxt > 2 then
              allRawParts[#allRawParts + 1] = rTxt
              chunkSegs[#chunkSegs + 1] = {
                startSec = startSec,
                endSec = startSec + chunkDur,
                text = cleanWhisperTranscript(rTxt)
              }
            end

            -- Full Gap & Stretched-Hallucination Recovery (leading, internal, trailing gaps > 12s OR stretched tiny segments > 13s)
            if chunkDur > 14.0 and not isCancelled() then
              local cleanChunkSegs = {}
              local missingWindows = {}

              -- Step A: Remove stretched Whisper 1-word hallucinations (e.g. >13s duration with <35 bytes text) and queue them for clean retry
              for _, cs in ipairs(chunkSegs) do
                local dur = cs.endSec - cs.startSec
                if dur > 13.0 and #(cs.text or "") < 35 then
                  missingWindows[#missingWindows + 1] = {s = cs.startSec, e = cs.endSec}
                else
                  cleanChunkSegs[#cleanChunkSegs + 1] = cs
                end
              end

              table.sort(cleanChunkSegs, function(a, b) return a.startSec < b.startSec end)

              -- Step B: Detect any leading, internal, or trailing gap > 12.0s
              local cursor = startSec
              for _, cs in ipairs(cleanChunkSegs) do
                if (cs.startSec - cursor) > 12.0 then
                  missingWindows[#missingWindows + 1] = {s = cursor, e = cs.startSec}
                end
                if cs.endSec > cursor then cursor = cs.endSec end
              end
              if ((startSec + chunkDur) - cursor) > 12.0 then
                missingWindows[#missingWindows + 1] = {s = cursor, e = startSec + chunkDur}
              end

              -- Step C: Re-transcribe each missing/stretched window cleanly with fresh context
              for wIdx, win in ipairs(missingWindows) do
                if isCancelled() then break end
                local wDur = win.e - win.s
                if wDur > 2.0 then
                  local gTxt, gSegs = encodeAndTranscribeWindow(win.s, wDur, tostring(cIdx) .. "_fix_" .. tostring(wIdx), "")
                  if gSegs and #gSegs > 0 then
                    for _, sg in ipairs(gSegs) do
                      local adjStart = win.s + sg.startSec
                      local adjEnd = math.min(win.e, win.s + sg.endSec)
                      if adjEnd > adjStart + 0.1 then
                        cleanChunkSegs[#cleanChunkSegs + 1] = {startSec = adjStart, endSec = adjEnd, text = sg.text}
                      end
                    end
                  elseif gTxt and #gTxt > 2 then
                    cleanChunkSegs[#cleanChunkSegs + 1] = {startSec = win.s, endSec = win.e, text = cleanWhisperTranscript(gTxt)}
                  end
                end
              end

              table.sort(cleanChunkSegs, function(a, b) return a.startSec < b.startSec end)
              chunkSegs = cleanChunkSegs
            end

            for _, cs in ipairs(chunkSegs) do
              allTimedSegments[#allTimedSegments + 1] = cs
            end

            if #chunkSegs > 0 then
              local lastTxt = chunkSegs[#chunkSegs].text or ""
              if not hasDevanagariChars(lastTxt) then
                if #lastTxt > 120 then lastTxt = lastTxt:sub(#lastTxt - 119) end
                prevPromptHint = lastTxt
              else
                prevPromptHint = ""
              end
            end
          end
        end
      else
        setProgress("Transcribing audio via free Whisper server...")
        local rTxt, rErr = transcribeWithHuggingFace(inputData)
        errDetail = rErr
        if rTxt and #rTxt > 2 then
          allRawParts[#allRawParts + 1] = rTxt
        end
      end

      if isCancelled() then return false, "Cancelled by user." end

      local rawTranscript = table.concat(allRawParts, " ")
      if (#rawTranscript < 2) and (#allTimedSegments == 0) then
        local hint = (gKey == nil or gKey == "")
          and "\n\nTip: Add your free Groq API Key in Studio Settings for fast, reliable Audio-to-Video transcription."
          or "\n\nTip: Please verify your Groq API Key in Studio Settings and check your internet connection."
        return false, "Speech recognition failed (" .. tostring(errDetail or "Unknown error") .. ")." .. hint
      end

      if #allTimedSegments > 0 then
        -- Merge tiny 1-word trailing orphan Whisper segments (e.g. lone "ہے") into previous segment
        local compactSegs = {}
        for _, seg in ipairs(allTimedSegments) do
          local wc = 0
          for _ in (seg.text or ""):gmatch("%S+") do wc = wc + 1 end
          if #compactSegs > 0 and wc <= 1 and #(seg.text or "") <= 12 and (seg.endSec - seg.startSec) < 2.2 then
            compactSegs[#compactSegs].text = compactSegs[#compactSegs].text .. " " .. seg.text
            compactSegs[#compactSegs].endSec = seg.endSec
          else
            compactSegs[#compactSegs + 1] = seg
          end
        end
        allTimedSegments = compactSegs

        if gKey and gKey ~= "" then
          setProgress("Proofreading Urdu subtitles with AI...")
          proofreadUrduSegmentsWithGroq(allTimedSegments, gKey)
        end

        local prevEnd = 0.0
        for i, seg in ipairs(allTimedSegments) do
          local txt = ensureCleanUrdu(seg.text)

          if i == 1 and seg.startSec > 3.0 then
            lineRecords[#lineRecords + 1] = {
              text = "",
              durSec = seg.startSec,
              sit = detectSituationTag(txt),
              imgPath = nil
            }
            prevEnd = seg.startSec
          end

          local segEnd = seg.endSec
          if i == #allTimedSegments and segEnd < totalAudioSec then
            segEnd = totalAudioSec
          end
          local segDur = math.max(0.7, segEnd - prevEnd)
          prevEnd = prevEnd + segDur

          local subLines = splitIntoLines(txt, hasNonAsciiChars(txt))
          if #subLines > 1 then
            local totalSubChars = 0
            for _, sl in ipairs(subLines) do totalSubChars = totalSubChars + math.max(1, #sl) end
            for _, sl in ipairs(subLines) do
              local frac = math.max(1, #sl) / math.max(1, totalSubChars)
              local subDur = math.max(0.7, segDur * frac)
              lineRecords[#lineRecords + 1] = {
                text = sl,
                durSec = subDur,
                sit = detectSituationTag(sl),
                imgPath = nil
              }
            end
          else
            local remDur = segDur
            while remDur > 0.4 do
              local slice = math.min(8.5, remDur)
              lineRecords[#lineRecords + 1] = {
                text = txt,
                durSec = slice,
                sit = detectSituationTag(txt),
                imgPath = nil
              }
              remDur = remDur - slice
            end
          end
        end
      else
        local transcript = cleanWhisperTranscript(rawTranscript)
        if hasDevanagariChars(transcript) then
          setProgress("Preparing Urdu subtitles and scenes...")
          local urduConv = translateLongText(transcript, "ur", "hi")
          if urduConv and #urduConv > 2 then
            transcript = cleanWhisperTranscript(urduConv)
          end
        end
        local lines = splitIntoLines(transcript, hasNonAsciiChars(transcript))
        local totalChars = 0
        for _, ln in ipairs(lines) do totalChars = totalChars + math.max(1, #ln) end
        for _, sText in ipairs(lines) do
          local frac = math.max(1, #sText) / math.max(1, totalChars)
          local durSec = math.max(1.2, totalAudioSec * frac)
          lineRecords[#lineRecords + 1] = {
            text = sText,
            durSec = durSec,
            sit = detectSituationTag(sText),
            imgPath = nil
          }
        end
      end
    end

    if isCancelled() then return false, "Cancelled by user." end

    -- Build overall story context summary (first ~450 chars) for the AI Scene Director
    local storyParts = {}
    local storyLen = 0
    for _, rec in ipairs(lineRecords) do
      if rec.text and rec.text ~= "" then
        storyParts[#storyParts + 1] = rec.text
        storyLen = storyLen + #rec.text
        if storyLen >= 950 then break end
      end
    end
    local storyOverview = table.concat(storyParts, " ")
    local characterBible = ""
    if gKey and gKey ~= "" and #storyOverview >= 30 then
      setProgress("Analyzing story & locking character appearances...")
      characterBible = buildCharacterBibleWithGroq(storyOverview, gKey)
    end

    local visualGroups = {}
    local curGroup = {indices = {}, texts = {}, dur = 0, sit = nil}
    for i, rec in ipairs(lineRecords) do
      local sitChanged = (curGroup.sit ~= nil) and (rec.sit ~= "general") and (rec.sit ~= curGroup.sit) and (curGroup.dur >= 3.5)
      if sitChanged and #curGroup.indices > 0 then
        visualGroups[#visualGroups + 1] = curGroup
        curGroup = {indices = {}, texts = {}, dur = 0, sit = nil}
      end
      curGroup.indices[#curGroup.indices + 1] = i
      if rec.text and rec.text ~= "" then
        curGroup.texts[#curGroup.texts + 1] = rec.text
      end
      curGroup.dur = curGroup.dur + rec.durSec
      if rec.sit ~= "general" then curGroup.sit = rec.sit end

      if curGroup.dur >= 9.0 or #curGroup.indices >= 3 or i == #lineRecords then
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

    local prevVisualDesc = ""

    local function fetchVisualImage(combinedText, sitTag, outJpg, sceneIdx)
      local directedVisual = nil
      if gKey and gKey ~= "" and combinedText ~= "" then
        directedVisual = directSceneWithGroq(storyOverview, characterBible, prevVisualDesc, combinedText, gKey)
      end

      local sceneCore = nil
      if directedVisual and #directedVisual >= 12 then
        sceneCore = directedVisual
        prevVisualDesc = directedVisual
      else
        local anchor = SITUATION_ANCHORS[sitTag or "general"] or SITUATION_ANCHORS.general
        local engScene = combinedText ~= "" and translateToEnglish(combinedText) or ""
        if #engScene > 130 then engScene = engScene:sub(1, 130) end
        sceneCore = enforceCharacterGender(sanitizeImagePrompt(anchor .. (engScene ~= "" and (". Scene action: " .. engScene) or "")), combinedText)
        prevVisualDesc = anchor
      end

      local positiveQuality = "photorealistic high resolution frame, natural lighting, crisp sharp details, clean balanced composition"
      local promptStr = sanitizeImagePrompt(sceneCore .. ". " .. stylePrompt .. ", " .. positiveQuality)
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
      local waits = {4000, 6000, 8000, 4000}

      for attempt = 1, 4 do
        if isCancelled() then return false end
        if downloadBinary(urls[attempt], outJpg, 50000, 12000) and isValidFullImage(outJpg) then
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
      if isCancelled() then return false, "Cancelled by user." end
      setProgress(string.format("Directing & Generating Scene %d of %d...", gIdx, #visualGroups))
      local jpgPath = workDir .. "/scene_" .. gIdx .. ".jpg"
      local combinedTxt = table.concat(grp.texts, " ")
      local okImg = fetchVisualImage(combinedTxt, grp.sit, jpgPath, gIdx)
      if isCancelled() then return false, "Cancelled by user." end
      if okImg then
        if not firstGoodImgPath then firstGoodImgPath = jpgPath end
        lastGoodImgPath = jpgPath
      end
      local assignedPath = okImg and jpgPath or lastGoodImgPath
      for _, lineIdx in ipairs(grp.indices) do
        lineRecords[lineIdx].imgPath = assignedPath
      end
      if gIdx < #visualGroups then
        sleepMs(3500)
      end
    end

    if firstGoodImgPath then
      for _, rec in ipairs(lineRecords) do
        if not rec.imgPath then rec.imgPath = firstGoodImgPath end
      end
    end

    if isCancelled() then return false, "Cancelled by user." end

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
      if isCancelled() then break end
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

    if isCancelled() then return false, "Cancelled by user." end

    setProgress("Rendering smooth HD video frames...")
    local tempVideoMp4 = workDir .. "/video_only.mp4"
    local fps = 20
    local frameDurUs = math.floor(1000000 / fps)

    local vFmt = MediaFormat.createVideoFormat("video/avc", vidW, vidH)
    vFmt.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
    vFmt.setInteger(MediaFormat.KEY_BIT_RATE, 3500000)
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

    local subPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    subPaint.setColor(Color.WHITE)
    subPaint.setTextSize(math.floor(math.min(vidW, vidH) * 0.046))
    subPaint.setTypeface(Typeface.DEFAULT_BOLD)
    subPaint.setShadowLayer(6.0, 2.0, 2.0, Color.BLACK)

    local cachedPath = nil
    local cachedBmp = nil
    local prevBmp = nil
    local cumSec = 0.0
    local cumFrames = 0

    for sIdx, rec in ipairs(lineRecords) do
      if isCancelled() then break end
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
      cumSec = cumSec + rec.durSec
      local targetCumFrames = math.floor(cumSec * fps + 0.5)
      local totalFrames = math.max(10, targetCumFrames - cumFrames)
      cumFrames = cumFrames + totalFrames

      local zoomIn = ((sIdx % 2) == 1)
      local fadeFrames = math.min(14, math.floor(totalFrames / 2))

      local subLayout = nil
      local subTy = 0
      local dynScrimTop = math.floor(vidH * 0.78)
      if drawSubs and rec.text and rec.text ~= "" then
        local textW = math.floor(vidW * 0.88)
        subLayout = StaticLayout(rec.text, subPaint, textW, Layout.Alignment.ALIGN_CENTER, 1.15, 0.0, false)
        local lh = subLayout.getHeight()
        subTy = vidH - lh - math.floor(vidH * 0.045)
        dynScrimTop = math.max(math.floor(vidH * 0.62), subTy - math.floor(vidH * 0.08))
        scrimPaint.setShader(LinearGradient(0, dynScrimTop, 0, vidH, Color.TRANSPARENT, Color.parseColor("#CC000000"), Shader.TileMode.CLAMP))
      end

      for f = 0, totalFrames - 1 do
        if isCancelled() then break end
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
            local half = math.max(1, math.floor(fadeFrames / 2))
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
            canvas.drawRect(0, dynScrimTop, vidW, vidH, scrimPaint)
            canvas.save()
            canvas.translate(math.floor(vidW * 0.06), subTy)
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

    if not isCancelled() then
      drainVideoEncoder(true)
    end
    pcall(function() vEncoder.stop() vEncoder.release() end)
    pcall(function() inputSurface.release() end)
    pcall(function() if vMuxStarted then vMuxer.stop() end vMuxer.release() end)

    if isCancelled() then return false, "Cancelled by user." end

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
  end, modeId, inputVal, fmt.w, fmt.h, sty.prompt, vce.id, transId, showSubs, CACHE_DIR, progressFile, cancelFlagFile, groqApiKey, function(ok, resOrErr, sceneCount)
    isGenerating = false
    pcall(function() btnGenerate.setEnabled(true) end)
    if statusTicker then
      pcall(function() statusTicker.stop() end)
      statusTicker = nil
    end
    pcall(function() progressDlg.dismiss() end)
    pcall(function() File(cancelFlagFile).delete() end)

    haptic(35)
    if ok then
      currentVideoPath = resOrErr
      currentVideoTitle = "AI_Video_" .. os.date("%Y%m%d_%H%M%S")
      cleanupOldCache(currentVideoPath)
      if isHiddenInBackground then
        sendReadyNotification(TOOL_TITLE, "Your video is ready!")
        pendingOutcome = {ok = true, sceneCount = sceneCount}
        isHiddenInBackground = false
        bringAppToFront()
      elseif isActivityPaused then
        sendReadyNotification(TOOL_TITLE, "Your video is ready!")
        pendingOutcome = {ok = true, sceneCount = sceneCount}
      else
        showVideoResultWindow(sceneCount)
      end
    else
      cleanupOldCache(currentVideoPath)
      if tostring(resOrErr) == "Cancelled by user." then
        Toast.makeText(activity, "Video generation cancelled.", Toast.LENGTH_SHORT).show()
        return
      end
      if isHiddenInBackground then
        sendReadyNotification(TOOL_TITLE, "Video generation failed.")
        pendingOutcome = {ok = false, err = resOrErr}
        isHiddenInBackground = false
        bringAppToFront()
      elseif isActivityPaused then
        sendReadyNotification(TOOL_TITLE, "Video generation failed.")
        pendingOutcome = {ok = false, err = resOrErr}
      else
        showErrorWindow(resOrErr)
      end
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
    dlgRoot.setBackground(makeGradBg("#240A34", "#0E0518", 22, "#D946EF", 2.0))
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
      "AI Video Maker Studio is a complete video creation studio that turns your written scripts or voice recordings of any length into ready-to-share HD MP4 videos with story-matched visuals, smooth transitions, and clear synchronized subtitles.",
      "#261806", "#140C03", "#F59E0B", "#FEF3C7"
    )

    addAboutCard(
      "Key Features",
      "• Text to Video Mode: Turn any Urdu or English script, story, or message into a full narrated HD video.\n• Audio to Video Mode: Use any short or long voice recording from your device to automatically generate matching scenes and synced subtitles.\n• Smart Visual Storytelling: Understands your topic (stories, Islamic greetings, daily updates, weather, or nature) and keeps recurring story characters consistent across scenes.\n• Accurate Urdu & English Subtitles: Automatically refines captions so text stays clean, readable, and properly timed with the voice.\n• Built-in Audio Browser: View all device audios, filter live as you type, and listen with inline Play/Pause before selecting.\n• Complete Customization: Choose from 3 video formats (YouTube Landscape, Shorts/Reels, Square), 6 visual styles, 5 narrator voices, 3 smooth transitions, and On/Off subtitles.\n• Background Mode & Built-in Player: Hide to Home Screen while rendering with a ready notification, then preview, rename, and save directly to Downloads.",
      "#06261E", "#041410", "#10B981", "#A7F3D0"
    )

    addAboutCard(
      "How to Use",
      "1. Enter your free Groq API Key during first-time setup (or anytime from Studio Settings).\n2. Select Text to Video or Audio to Video from the Select Mode dropdown.\n3. Paste your script or choose any audio recording using the built-in Audio Browser.\n4. Pick your Video Format, Visual Style, Voice, Transition, and Subtitles.\n5. Tap GENERATE FULL VIDEO (tap HIDE anytime to continue in the background).\n6. Preview your finished video in the built-in player, rename it if desired, and tap DOWNLOAD MP4.",
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

function onPause()
  isActivityPaused = true
end

function onResume()
  isActivityPaused = false
  if pendingOutcome then
    local out = pendingOutcome
    pendingOutcome = nil
    Handler(Looper.getMainLooper()).postDelayed(Runnable{
      run = function()
        if out.ok then
          showVideoResultWindow(out.sceneCount)
        else
          showErrorWindow(out.err)
        end
      end
    }, 150)
  end
end

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
      local setupDone = prefs.getBoolean("welcome_setup_v1_done", false)
      if not setupDone then
        showFirstTimeWelcomeDialog(function()
          pcall(function()
            if btnGroqKey then
              btnGroqKey.setText(getGroqBtnText())
            end
          end)
        end)
      end
    end
  }, 220)
end)
