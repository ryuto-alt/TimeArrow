-- 4枚目を先読み連続スクロール ステージ選択
local STAGES = {
  { path = "scenes/stage1.json", name = "遅れ橋の丘", thumbnail = "textures/ui/stage1.png" },
  { path = "scenes/stage2.json", name = "時限の回廊", thumbnail = "textures/ui/stage2.png" },
  { path = "scenes/stage3.json", name = "風わたる谷", thumbnail = "textures/ui/stage3.png" },
  { path = "scenes/stage4.json", name = "歯車の工房", thumbnail = "textures/ui/stage4.png" },
  { path = "scenes/stage5.json", name = "時果ての塔", thumbnail = "textures/ui/stage5.png" },
}

local ENTER_AT = 0.45
local TRANSITION_DUR = 0.42
local BUFFER_RESET_DURATION = 0.02
local CARD_SHIFT = 483.0
local BUFFER_RESET_DISTANCE = 1932.0
local CENTER_TO_SIDE_SCALE = 0.41
local SIDE_TO_CENTER_SCALE = 2.48
local SIDE_VERTICAL_SHIFT = 142.5

local index = 1
local state = "idle"
local optionsOpen = false
local transitionTime = 0
local transitionDirection = 1
local entryTime = 0
local leaving = false

local previousThumbnail
local centerThumbnail
local nextThumbnail
local bufferThumbnail
local largeBaseThumbnail
local previousTitle
local nextTitle
local cardTitle
local cardNumber

--- Wraps an arbitrary stage index so every configured stage participates in the carousel.
local function wrappedIndex(value)
  return ((value - 1) % #STAGES) + 1
end

--- Returns the configured stage at an offset from the currently selected stage.
local function stageAt(offset)
  return STAGES[wrappedIndex(index + offset)]
end

--- Returns whether an optional entity can receive UI commands.
local function isValid(entity)
  return entity and entity:isValid()
end

--- Updates the visible cards plus the off-screen card that will enter on the next move.
local function refreshCarouselContent()
  local previous = stageAt(-1)
  local selected = stageAt(0)
  local next = stageAt(1)
  local buffered = stageAt(2)

  -- Each physical card keeps its own stage data while roles rotate after a transition.
  scene:setUiTexture(previousThumbnail, previous.thumbnail)
  scene:setUiTexture(centerThumbnail, selected.thumbnail)
  scene:setUiTexture(nextThumbnail, next.thumbnail)
  scene:setUiTexture(bufferThumbnail, buffered.thumbnail)
  scene:setUiText(previousTitle, previous.name)
  scene:setUiText(nextTitle, next.name)
  scene:setUiText(cardTitle, selected.name)
  scene:setUiText(cardNumber, index .. " / " .. #STAGES)
end

--- Returns the absolute scale that renders a physical card at side-card size.
local function sideScale(entity)
  if entity == largeBaseThumbnail then
    return CENTER_TO_SIDE_SCALE
  end
  return 1
end

--- Returns the absolute scale that renders a physical card at center-card size.
local function centerScale(entity)
  if entity == largeBaseThumbnail then
    return 1
  end
  return SIDE_TO_CENTER_SCALE
end

--- Applies the visual hierarchy for the current physical card roles.
local function applyCardTreatment()
  -- Card colors stay opaque; alpha is animated separately so a side card can brighten as it reaches center.
  scene:setUiColor(previousThumbnail, 0.72, 0.82, 1, 1)
  scene:setUiColor(centerThumbnail, 1, 1, 1, 1)
  scene:setUiColor(nextThumbnail, 0.72, 0.82, 1, 1)
  scene:setUiColor(bufferThumbnail, 0.72, 0.82, 1, 1)

  scene:tweenUi(previousThumbnail, { alpha = 0.72, scale = sideScale(previousThumbnail), duration = 0.001 })
  scene:tweenUi(centerThumbnail, { alpha = 1, scale = centerScale(centerThumbnail), duration = 0.001 })
  scene:tweenUi(nextThumbnail, { alpha = 0.72, scale = sideScale(nextThumbnail), duration = 0.001 })
  scene:tweenUi(bufferThumbnail, { alpha = 0, scale = sideScale(bufferThumbnail), duration = 0.001 })
end

--- Fades side captions while their corresponding thumbnail trades positions.
local function fadeSideTitles(alpha, duration)
  for _, entity in ipairs({ previousTitle, nextTitle }) do
    if isValid(entity) then
      scene:tweenUi(entity, { alpha = alpha, duration = duration, easing = "inOut" })
    end
  end
end

--- Moves the right buffer to the left preload position before it enters during a reverse transition.
local function beginLeftBufferEntrance()
  local enteringCard = bufferThumbnail

  -- Tween replacement is deterministic only after the reset has been applied on a separate update.
  scene:tweenUi(enteringCard, {
    dx = -BUFFER_RESET_DISTANCE, alpha = 0, scale = sideScale(enteringCard), duration = BUFFER_RESET_DURATION,
  })
  time.after(BUFFER_RESET_DURATION, function()
    if state ~= "transitioning" or transitionDirection >= 0 or bufferThumbnail ~= enteringCard then return end

    scene:tweenUi(enteringCard, {
      dx = CARD_SHIFT, scale = sideScale(enteringCard), alpha = 1, duration = TRANSITION_DUR, easing = "inOut",
    })
  end)
end

--- Returns the actual duration of the transition currently being animated.
local function activeTransitionDuration()
  if transitionDirection < 0 then
    return TRANSITION_DUR + BUFFER_RESET_DURATION
  end
  return TRANSITION_DUR
end

--- Rotates card references after a rightward move and recycles the exited card off-screen.
local function completeRightTransition()
  local exited = previousThumbnail
  previousThumbnail = centerThumbnail
  centerThumbnail = nextThumbnail
  nextThumbnail = bufferThumbnail
  bufferThumbnail = exited

  -- The exited card is invisible while it teleports to the next right-side buffer position.
  scene:tweenUi(bufferThumbnail, {
    dx = BUFFER_RESET_DISTANCE, alpha = 0, scale = sideScale(bufferThumbnail), duration = 0.001,
  })
end

--- Rotates card references after a leftward move; the exited card already rests at the right buffer.
local function completeLeftTransition()
  local exited = nextThumbnail
  nextThumbnail = centerThumbnail
  centerThumbnail = previousThumbnail
  previousThumbnail = bufferThumbnail
  bufferThumbnail = exited
end

--- Starts a four-card continuous carousel transition in the requested direction.
function beginTransition(direction)
  if state ~= "idle" or leaving or #STAGES < 2 then return end

  audio:playSFX("audio/ui/menu_select.wav", false)
  state = "transitioning"
  transitionTime = 0
  transitionDirection = direction
  fadeSideTitles(0, 0.12)

  if direction > 0 then
    -- Left exits, center becomes left, right becomes center, and the buffer becomes right.
    scene:tweenUi(previousThumbnail, {
      dx = -CARD_SHIFT, scale = sideScale(previousThumbnail), alpha = 0, duration = TRANSITION_DUR, easing = "inOut",
    })
    scene:tweenUi(centerThumbnail, {
      dx = -CARD_SHIFT, dy = SIDE_VERTICAL_SHIFT, scale = sideScale(centerThumbnail), alpha = 0.72,
      duration = TRANSITION_DUR, easing = "inOut",
    })
    scene:tweenUi(nextThumbnail, {
      dx = -CARD_SHIFT, dy = -SIDE_VERTICAL_SHIFT, scale = centerScale(nextThumbnail), alpha = 1,
      duration = TRANSITION_DUR, easing = "inOut",
    })
    scene:tweenUi(bufferThumbnail, {
      dx = -CARD_SHIFT, scale = sideScale(bufferThumbnail), alpha = 1, duration = TRANSITION_DUR, easing = "inOut",
    })
  else
    -- The buffer first resets to the hidden left preload position, then enters on the following update.
    beginLeftBufferEntrance()
    scene:tweenUi(nextThumbnail, {
      dx = CARD_SHIFT, scale = sideScale(nextThumbnail), alpha = 0, duration = TRANSITION_DUR, easing = "inOut",
    })
    scene:tweenUi(centerThumbnail, {
      dx = CARD_SHIFT, dy = SIDE_VERTICAL_SHIFT, scale = sideScale(centerThumbnail), alpha = 0.72,
      duration = TRANSITION_DUR, easing = "inOut",
    })
    scene:tweenUi(previousThumbnail, {
      dx = CARD_SHIFT, dy = -SIDE_VERTICAL_SHIFT, scale = centerScale(previousThumbnail), alpha = 1,
      duration = TRANSITION_DUR, easing = "inOut",
    })
  end
end

--- Finalizes stage data only after every visible card has reached its new continuous position.
local function completeTransition()
  if transitionDirection > 0 then
    completeRightTransition()
  else
    completeLeftTransition()
  end

  index = wrappedIndex(index + transitionDirection)
  refreshCarouselContent()
  applyCardTreatment()
  fadeSideTitles(1, 0.16)
  state = "idle"
end

--- Starts the selected stage after a short confirmation animation.
function goPlay()
  if leaving then return end
  leaving = true

  audio:playSFX("audio/ui/menu_enter.wav", false)
  if isValid(centerThumbnail) then
    uifx.punch(centerThumbnail, 1.08, 0.22)
  end

  local path = stageAt(0).path
  time.after(0.22, function()
    transitionToScene(path, 4, 0.9)
  end)
end

--- Returns from stage select to the title screen.
function goBack()
  if leaving then return end
  leaving = true
  audio:playSFX("audio/ui/menu_select.wav", false)
  goToScene("scenes/title.json", 0.4)
end

--- Initializes card references, visual content, and menu events when the scene starts.
function OnStart(self)
  audio:setBGMVolume(loadNum("bgm_restore", audio:getBGMVolume()))
  audio:playBGM("audio/bgm/select_clock_piano.mp3", true)

  previousThumbnail = scene:findEntity("StageThumbnailPrevious")
  centerThumbnail = scene:findEntity("StageCardPanel")
  largeBaseThumbnail = centerThumbnail
  nextThumbnail = scene:findEntity("StageThumbnailNext")
  bufferThumbnail = scene:findEntity("StageThumbnailBuffer")
  previousTitle = scene:findEntity("StageThumbnailPreviousTitle")
  nextTitle = scene:findEntity("StageThumbnailNextTitle")
  cardTitle = scene:findEntity("StageCardTitle")
  cardNumber = scene:findEntity("StageCardNumber")

  index = 1
  refreshCarouselContent()
  applyCardTreatment()
  -- The preload card is editor-hidden but enabled before it begins moving in play mode.
  scene:showUi(bufferThumbnail)
  scene:tweenUi(bufferThumbnail, { alpha = 0, duration = 0.001 })

  -- The three visible cards enter together; the buffer remains outside the viewport.
  for _, entity in ipairs({
    previousThumbnail, centerThumbnail, nextThumbnail,
    previousTitle, nextTitle, cardTitle, cardNumber,
  }) do
    if isValid(entity) then
      scene:tweenUi(entity, { alpha = 0, scale = 0.82, duration = 0.001 })
      local targetAlpha = (entity == previousThumbnail or entity == nextThumbnail) and 0.72 or 1
      scene:tweenUi(entity, {
        alpha = targetAlpha, scale = (entity == centerThumbnail) and centerScale(entity) or sideScale(entity), duration = 0.72,
        delay = ENTER_AT + 0.20, easing = "back",
      })
    end
  end

  events:on("stage_prev", function() beginTransition(-1) end)
  events:on("stage_next", function() beginTransition(1) end)
  events:on("stage_play", function() goPlay() end)
  events:on("stage_back", function() goBack() end)

  -- オプション(ESC/☰)が開いている間: 自分のキャンバスを隠してフォーカスナビの逃げ先を消す
  local selectCanvas = scene:findEntity("SelectCanvas")
  events:on("options_open", function()
    optionsOpen = true
    if isValid(selectCanvas) then scene:hideUi(selectCanvas) end
  end)
  events:on("options_close", function()
    optionsOpen = false
    if isValid(selectCanvas) then scene:showUi(selectCanvas) end
  end)
end

-- 背景の歯車(Blenderレイヤー出し UI画像)をゆっくり回す。隣り合う歯車は逆回転。
-- オプション中/退場中も回し続ける(背景は生きたまま)。
local GEAR_SPINS = {
  { name = "SelectGear_gearL1", speed = 8 },
  { name = "SelectGear_gearL2", speed = -11 },
  { name = "SelectGear_gearR1", speed = -7 },
  { name = "SelectGear_gearR2", speed = 10 },
}

local function spinGears(dt)
  for _, s in ipairs(GEAR_SPINS) do
    s.e = s.e or scene:findEntity(s.name)
    if isValid(s.e) then
      scene:setUiRotation(s.e, (scene:getUiRotation(s.e) + s.speed * dt) % 360)
    end
  end
end

--- Advances the transition timer and routes keyboard, gamepad, and button input.
function OnUpdate(self, dt)
  spinGears(dt)
  if leaving or optionsOpen then return end
  entryTime = entryTime + dt

  if state == "transitioning" then
    transitionTime = transitionTime + dt
    if transitionTime >= activeTransitionDuration() then
      completeTransition()
    end
  end

  if state == "idle" and entryTime > 1.6 then
    if keyPressed("LEFT") or keyPressed("A") or padPressed("DPAD_LEFT") then beginTransition(-1) end
    if keyPressed("RIGHT") or keyPressed("D") or padPressed("DPAD_RIGHT") then beginTransition(1) end
    if keyPressed("SPACE") or keyPressed("ENTER") or padPressed("A") then goPlay() end
    -- ESC はオプションメニュー(OptionsMenu.lua)に譲る。タイトルへ戻るのはパッドB/BACKボタン
    if padPressed("B") then goBack() end
  end
end
