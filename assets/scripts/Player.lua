-- Player.lua -- 「時を先送りさせる矢」プレイヤー本体。
-- 横視点プラットフォーマー(独自の重力/移動を手書き。Joltは使わない)。カメラは固定(GameCamera側で
-- 静止設定済み、Playerは一切動かさない)。
-- 弓矢: 1本のみ所持。L/RBを引き絞る(移動ロック・矢印キー/WASDで8方向照準・引いた秒数でスキップ量が変化)→
--        離すと発射。刺さったオブジェクトに触れる(=矢が刺さった"その場"に触れる)ことで回収できる。
-- 死亡(落下)は自分では巻き戻さず、events:emit("player_died") で GameManager に委ねる(シーン再読込で全リセット)。
--
-- 当たり判定の統一ルール: 全てのスプライトエンティティは sprite2d.size=(1,1) 固定・
-- transform.scale が実寸(=当たり判定サイズ)を兼ねる。円判定は使わず、全てtransform.scaleから
-- 半径(半幅/半高)を出すAABBで判定する(スプライトの見た目と完全一致させるため)。
properties = {
  { name = "speed",        type = "float",  default = 6.0,  min = 1,  max = 15, label = "移動速度" },
  { name = "jumpSpeed",     type = "float",  default = 12.5, min = 1,  max = 20, label = "ジャンプ初速" },
  { name = "gravity",       type = "float",  default = 22.0, min = 1,  max = 60, label = "重力加速度" },
  { name = "groundY",       type = "float",  default = 0.0,                     label = "地面のY" },
  { name = "halfW",         type = "float",  default = 0.4,  min = 0.1, max = 2, label = "当たり半幅(見た目より少し小さめ。手足の広がり分を除外)" },
  { name = "halfHeight",    type = "float",  default = 0.55, min = 0.1, max = 3, label = "当たり半高(scale.yの半分と合わせる/接地オフセット)" },
  { name = "arrowSpeed",    type = "float",  default = 15.0, min = 1,  max = 40, label = "矢の速度(等速直線運動)" },
  { name = "arrowRange",    type = "float",  default = 18.0, min = 1,  max = 60, label = "矢の最大飛距離" },
  { name = "arrowHalf",     type = "float",  default = 0.1,  min = 0.02,max = 1, label = "矢自体の当たり半径(先端の太さ)" },
  { name = "minSkip",       type = "float",  default = 2.0,  min = 0,  max = 20, label = "最小先送り量(軽く引いた時)" },
  { name = "maxSkip",       type = "float",  default = 10.0, min = 0,  max = 30, label = "最大先送り量(引き絞りきった時)" },
  { name = "maxDrawTime",   type = "float",  default = 3.0,  min = 0.2, max = 8, label = "引き絞り最大秒数" },
  { name = "aimTurnSpeed",  type = "float",  default = 270.0,min = 30,  max = 1080,label = "照準の旋回速度(度/秒。WASDでいきなり真上/真下にならないように)" },
  { name = "climbSpeed",    type = "float",  default = 4.0,  min = 1,  max = 12, label = "ツタを登る速度" },
  { name = "targets",       type = "string", default = "",                      label = "先送り対象(カンマ区切り)" },
  { name = "standables",    type = "string", default = "",                      label = "乗れる足場(カンマ区切り)" },
  { name = "climbables",    type = "string", default = "",                      label = "登れる蔦等(カンマ区切り)" },
  { name = "pits",          type = "string", default = "",                      label = "床が無い落とし穴マーカー(カンマ区切り)" },
  { name = "solids",        type = "string", default = "",                      label = "矢は貫通するが物理的に通れない壁(格子等、カンマ区切り)" },
  { name = "mirrors",       type = "string", default = "",                      label = "矢を反射する鏡(カンマ区切り。rotation.zで向き=0:'/' 90:'\\')" },
  { name = "maxBounces",    type = "int",    default = 4,   min = 1,  max = 10, label = "矢が反射できる最大回数" },
}

-- プレイヤーの表示状態を、補助スプライトの名前で一元管理する。
local PLAYER_SPRITE_NAMES = {
  idle = "PlayerIdleSprite",
  run = "PlayerRunSprite",
  jump = "PlayerJumpSprite",
  bow = "PlayerBowSprite",
}

-- 状態ごとのスプライトアニメーション設定を一つにまとめる。
local PLAYER_ANIMATION_SETTINGS = {
  idle = { frames = 0, fps = 0, cols = 0, row = 0 },
  run = { frames = 6, fps = 10, cols = 6, row = 0 },
  jump = { frames = 7, fps = 8, cols = 7, row = 0 },
  bow = { frames = 0, fps = 0, cols = 0, row = 0 },
}

local function trimSplit(csv)
  local out = {}
  for w in string.gmatch(csv or "", "[^,]+") do
    local name = w:match("^%s*(.-)%s*$")
    if name ~= "" then out[#out + 1] = name end
  end
  return out
end

-- 半幅/半高同士のAABB重なり判定(スプライトの実寸=transform.scaleに基づく)
local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  local p = self.transform.position
  self.startX, self.startY, self.startZ = p.x, p.y, p.z
  self.vx, self.vy = 0, 0
  self.facing = 1
  self.grounded = false
  self.climbing = false
  self.fellOnce = false

  self.hasArrow = true
  self.arrowFlying = false
  self.arrowStuck = false
  self.arrowVX, self.arrowVY = 0, 0
  self.stuckX, self.stuckY = 0, 0
  self.stuckTarget = nil

  self.drawing = false
  self.drawT = 0
  self.aimX, self.aimY = 1, 0
  self.pendingAmount = self.minSkip

  -- 各状態の表示用エンティティを取得し、初期状態を待機にする。
  self.playerSprites = {}
  for state, name in pairs(PLAYER_SPRITE_NAMES) do
    local sprite = scene:findEntity(name)
    if sprite and sprite:isValid() then self.playerSprites[state] = sprite end
  end
  -- Sprite2D APIへ渡すPlayer本体のEntity userdataを取得する。
  self.playerEntity = scene:findEntity("Player")
  -- 元のPlayerスプライトは補助スプライトと重ならないよう非表示にする。
  if self.playerEntity and self.playerEntity:isValid() then
    scene:setSpriteAlpha(self.playerEntity, 0.0)
  end
  self.playerVisualState = nil
  self.bowTimer = 0

  self.targetList = trimSplit(self.targets)
  self.standList  = trimSplit(self.standables)
  self.climbList  = trimSplit(self.climbables)
  self.pitList    = trimSplit(self.pits)
  self.solidList  = trimSplit(self.solids)
  self.mirrorList = trimSplit(self.mirrors)
  self.bounces    = 0
  self.standPrevX = {}
  self.standTopY  = nil
  self.standDX    = 0

  -- 早送り中で実体のない solid(CrushWall等)。名前→残り秒。期間中は物理ブロックしない
  self.ghostSolids = {}
  events:on("solid_ghost", function(data)
    if data.target then self.ghostSolids[data.target] = data.duration or 0.35 end
  end)

  -- 開始位置が地面に埋まっていた場合の保険として、初回のみ接地高さへスナップする
  if p.y < self.groundY + self.halfHeight then
    self.transform.position = Vec3.new(p.x, self.groundY + self.halfHeight, p.z)
    self.startY = self.groundY + self.halfHeight
  end

  -- 矢オブジェクトは開始時は画面外(下方)に隠しておく
  local arrowE = scene:findEntity("Arrow")
  if arrowE and arrowE:isValid() then
    arrowE.transform.position = Vec3.new(0, -100, 0)
  end
end

-- 表示用スプライトをPlayer本体と同じ位置・向き・大きさへ同期する。
local function syncPlayerSpriteTransform(self)
  local transform = self.transform
  for _, sprite in pairs(self.playerSprites or {}) do
    if sprite and sprite:isValid() then
      sprite.transform.position = Vec3.new(transform.position.x, transform.position.y, transform.position.z)
      sprite.transform.rotation = Vec3.new(transform.rotation.x, transform.rotation.y, transform.rotation.z)
      sprite.transform.scale = Vec3.new(transform.scale.x, transform.scale.y, transform.scale.z)
    end
  end
end

-- 待機・走行・ジャンプ・弓の表示を切り替え、状態変更時だけ再生位置をリセットする。
local function setPlayerVisualState(self, state)
  if self.playerVisualState == state then
    syncPlayerSpriteTransform(self)
    return
  end

  self.playerVisualState = state
  local setting = PLAYER_ANIMATION_SETTINGS[state]
  for name, sprite in pairs(self.playerSprites or {}) do
    if sprite and sprite:isValid() then
      scene:setSpriteAlpha(sprite, name == state and 1.0 or 0.0)
      if name == state and setting then
        scene:setSpriteAnim(sprite, setting.frames, setting.fps, setting.cols, setting.row)
        scene:setSpriteAnimMode(sprite, 0)
      end
    end
  end
  syncPlayerSpriteTransform(self)
end

-- 物理状態と弓操作状態から、現在表示すべきプレイヤー状態を決める。
local function updatePlayerVisual(self)
  local state = "idle"
  if self.drawing or self.bowTimer > 0 then
    state = "bow"
  elseif not self.grounded or self.climbing then
    state = "jump"
  elseif math.abs(self.vx or 0) > 0.01 then
    state = "run"
  end
  setPlayerVisualState(self, state)
end

-- 乗れる足場(standables)を毎フレーム探し、水平範囲内かつ足元がだいたい上面以上なら
-- self.standTopY(上面Y)/self.standDX(その足場の今フレームの水平移動量)を更新する。
local function updateStandables(self, dt)
  self.standTopY = nil
  self.standDX = 0
  for _, name in ipairs(self.standList) do
    local e = scene:findEntity(name)
    if e and e:isValid() then
      local ep, es = e.transform.position, e.transform.scale
      local halfW = es.x * 0.5
      local topY = ep.y + es.y * 0.5
      local p = self.transform.position
      if math.abs(p.x - ep.x) <= halfW + 0.25 then
        local footY = p.y - self.halfHeight
        if footY >= topY - 0.3 and (not self.standTopY or topY > self.standTopY) then
          self.standTopY = topY
          self.standDX = ep.x - (self.standPrevX[name] or ep.x)
        end
      end
      self.standPrevX[name] = ep.x
    end
  end
end

-- pits(落とし穴マーカー)の水平範囲内にいて、かつどの standable にも乗っていなければ
-- 床が無いことにする(=groundYの平らな床を無視して落下する)。
local function overPit(self)
  for _, name in ipairs(self.pitList) do
    local e = scene:findEntity(name)
    if e and e:isValid() then
      local p, s = e.transform.position, e.transform.scale
      if math.abs(self.transform.position.x - p.x) <= s.x * 0.5 then return true end
    end
  end
  return false
end

-- 矢は貫通するが物理的に通れない壁(格子等)。既に重なっている相手から離れる動きは許可(脱出可)。
local function blockedBySolid(self, nx)
  local p = self.transform.position
  for _, name in ipairs(self.solidList) do
    local e = scene:findEntity(name)
    if e and e:isValid() and not (self.ghostSolids[name] and self.ghostSolids[name] > 0) then
      local ep, es = e.transform.position, e.transform.scale
      local hw, hh = es.x * 0.5, es.y * 0.5
      if math.abs(p.y - ep.y) < (self.halfHeight + hh) then
        local newOverlap = math.abs(nx - ep.x) < (self.halfW + hw)
        if newOverlap then
          local curOverlap = math.abs(p.x - ep.x) < (self.halfW + hw)
          local away = curOverlap and (math.abs(nx - ep.x) > math.abs(p.x - ep.x))
          if not away then return true end
        end
      end
    end
  end
  return false
end

-- 登れる蔦(climbables)に重なっていて、かつ上下キーを押している間だけ重力を上書きしてよじ登る。
-- 蔦がまだ育っていない(scale/位置的に重ならない)間は自然に触れられない=別途の状態管理が不要。
local function updateClimb(self, dt)
  self.climbing = false
  if self.drawing then return end

  local pp = self.transform.position
  local overlapping = false
  for _, name in ipairs(self.climbList) do
    local e = scene:findEntity(name)
    if e and e:isValid() then
      local p, s = e.transform.position, e.transform.scale
      local halfW, halfH = s.x * 0.5, s.y * 0.5
      if math.abs(pp.x - p.x) <= halfW + 0.3 and math.abs(pp.y - p.y) <= halfH + self.halfHeight * 0.6 then
        overlapping = true
        break
      end
    end
  end
  if not overlapping then return end

  local up = 0
  if keyDown("UP") or keyDown("W") then up = up + 1 end
  if keyDown("DOWN") or keyDown("S") then up = up - 1 end
  if up == 0 then
    local _, sy = padStick("left")
    if math.abs(sy) > 0.25 then up = sy end
  end
  if up == 0 then return end  -- 触れてるだけなら普通に重力任せ(手を伸ばして掴んでる間だけ登る)

  self.climbing = true
  self.vx = 0
  self.vy = up * self.climbSpeed
end

local function updateMovement(self, dt)
  local move = 0
  if not self.drawing then
    if keyDown("LEFT") or keyDown("A") then move = move - 1 end
    if keyDown("RIGHT") or keyDown("D") then move = move + 1 end
    if padDown("DPAD_LEFT") then move = move - 1 end
    if padDown("DPAD_RIGHT") then move = move + 1 end
    if move == 0 then
      local sx = padStick("left")
      if math.abs(sx) > 0.2 then move = sx end
    end
  end
  if move ~= 0 then self.facing = move > 0 and 1 or -1 end
  self.vx = move * self.speed

  if not self.drawing and self.grounded and (keyPressed("SPACE") or keyPressed("UP") or keyPressed("W") or padPressed("A")) then
    self.vy = self.jumpSpeed
    self.grounded = false
  end

  updateClimb(self, dt)  -- 登り中なら vx/vy をここで上書き
  if not self.climbing then
    self.vy = self.vy - self.gravity * dt
  end

  local p = self.transform.position
  local nx = p.x + self.vx * dt + self.standDX
  local ny = p.y + self.vy * dt

  if blockedBySolid(self, nx) then nx = p.x end

  -- 通常は平らな地面(groundY)だが、pitマーカーの範囲内では地面が無いことにする。
  -- standables(乗れる足場)はそれが地面より高ければ底上げする(隠れた/埋まった足場は無視される)。
  local restY = overPit(self) and nil or (self.groundY + self.halfHeight)
  if self.standTopY then
    local standRest = self.standTopY + self.halfHeight
    restY = restY and math.max(restY, standRest) or standRest
  end
  if not self.climbing and restY and ny <= restY then
    ny = restY
    self.vy = 0
    self.grounded = true
  else
    self.grounded = false
  end

  self.transform.position = Vec3.new(nx, ny, p.z)
  self.transform.rotation = Vec3.new(0, self.facing < 0 and 180 or 0, 0)

  if ny < -8 and not self.fellOnce then
    self.fellOnce = true
    events:emit("player_died", {})
  end
end

-- 入力から「狙いたい方向」を出す(離散8方向 or アナログ)。無入力なら向いてる方。
-- これは目標角度であって、実際の照準はupdateDraw内でaimAngleを毎フレーム少しずつ
-- 近づけていく(WASDでいきなり真上/真下を向かず、だんだん回転するように)。
local function aimTargetDir(self)
  local ax, ay = 0, 0
  if keyDown("LEFT") or keyDown("A") then ax = ax - 1 end
  if keyDown("RIGHT") or keyDown("D") then ax = ax + 1 end
  if keyDown("UP") or keyDown("W") then ay = ay + 1 end
  if keyDown("DOWN") or keyDown("S") then ay = ay - 1 end
  if ax == 0 and ay == 0 then
    local sx, sy = padStick("left")
    if math.abs(sx) > 0.35 or math.abs(sy) > 0.35 then ax, ay = sx, sy end
  end
  if ax == 0 and ay == 0 then return self.facing, 0 end
  local len = math.sqrt(ax * ax + ay * ay)
  return ax / len, ay / len
end

local function fireArrow(self)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then return end

  local amount = lerp(self.minSkip, self.maxSkip, clamp(self.drawT / self.maxDrawTime, 0, 1))
  local ax, ay = self.aimX or self.facing, self.aimY or 0
  local p = self.transform.position
  local sx, sy, sz = p.x + ax * 0.7, p.y + 0.2 + ay * 0.3, p.z
  arrowE.transform.position = Vec3.new(sx, sy, sz)
  arrowE.transform.rotation = Vec3.new(0, 0, math.deg(math.atan(ay, ax)))
  FX.spark(sx, sy, sz, 10, 0.3, 0.75, 1.0)

  self.hasArrow = false
  self.arrowFlying = true
  self.arrowVX, self.arrowVY = ax * self.arrowSpeed, ay * self.arrowSpeed
  self.shotFromX, self.shotFromY = p.x, p.y
  self.pendingAmount = amount
  self.bounces = 0
  self.drawT = 0
  -- 発射直後も弓を短時間表示して、引き絞りから発射までの動きを途切れさせない。
  self.bowTimer = 0.2
end

-- 飛翔中の矢が鏡(mirrors)に重なっていれば反射する(消費せず飛び続ける)。
-- 鏡のrotation.zが90度付近="\"向き、それ以外(既定0度)="/"向きとして扱う。
-- 反射したら true を返す(この関数を呼んだ側は今フレームの他の当たり判定をスキップする)。
local function tryReflect(self, arrowE, nx, ny)
  if self.bounces >= self.maxBounces then return false end
  for _, name in ipairs(self.mirrorList) do
    local m = scene:findEntity(name)
    if m and m:isValid() then
      local mp, ms = m.transform.position, m.transform.scale
      if overlapAABB(nx, ny, self.arrowHalf, self.arrowHalf, mp.x, mp.y, ms.x * 0.5, ms.y * 0.5) then
        local rz = m.transform.rotation.z % 180
        local backslash = rz > 45 and rz < 135
        if backslash then
          self.arrowVX, self.arrowVY = -self.arrowVY, -self.arrowVX
        else
          self.arrowVX, self.arrowVY = self.arrowVY, self.arrowVX
        end
        self.bounces = self.bounces + 1
        -- 同じ鏡へ連続ヒットしないよう、反射後の進行方向へ少し押し出す
        local px = nx + (self.arrowVX > 0 and 1 or -1) * 0.15
        local py = ny + (self.arrowVY > 0 and 1 or -1) * 0.15
        arrowE.transform.position = Vec3.new(px, py, mp.z)
        arrowE.transform.rotation = Vec3.new(0, 0, math.deg(math.atan(self.arrowVY, self.arrowVX)))
        FX.spark(nx, ny, mp.z, 10, 0.6, 0.9, 1.0)
        fx:pulse(0.1)
        return true
      end
    end
  end
  return false
end

-- 引き絞り(L/RB長押し): 移動ロック・矢印キー/WASDで8方向照準・離すと発射
local function updateDraw(self, dt)
  -- キーボードはWin32仮想キーコード76(L)で判定し、パッドはRBを使用する。
  local drawHeld = input:isKeyDown(76) or padDown("RB")
  local canDraw = self.hasArrow and not self.arrowFlying and not self.arrowStuck

  if drawHeld and canDraw then
    if not self.drawing then
      self.drawing = true
      self.drawT = 0
      self.aimAngle = math.deg(math.atan(self.aimY or 0, self.aimX or self.facing))
    end
    self.drawT = math.min(self.drawT + dt, self.maxDrawTime)

    -- 目標方向へ aimTurnSpeed(度/秒)で少しずつ回す(WASDでも滑らかに旋回する照準)
    local tx, ty = aimTargetDir(self)
    local targetAngle = math.deg(math.atan(ty, tx))
    local delta = angleDelta(self.aimAngle, targetAngle)
    local maxStep = self.aimTurnSpeed * dt
    self.aimAngle = self.aimAngle + clamp(delta, -maxStep, maxStep)
    local rad = math.rad(self.aimAngle)
    local ax, ay = math.cos(rad), math.sin(rad)
    self.aimX, self.aimY = ax, ay

    local p = self.transform.position
    local frac = self.drawT / self.maxDrawTime
    local len = 1.1 + 2.3 * frac
    FX.beam(p.x, p.y + 0.2, p.z, p.x + ax * len, p.y + 0.2 + ay * len, p.z,
            0.4 + 0.4 * frac, 0.75 + 0.2 * frac, 1.0, 0.1, "energy", 3 + frac * 3)
  elseif self.drawing then
    self.drawing = false
    fireArrow(self)
  end
end

local function stickArrow(self, arrowE, hitTargetName)
  local ap = arrowE.transform.position
  self.arrowFlying = false
  self.arrowStuck = true
  self.stuckX, self.stuckY = ap.x, ap.y
  self.stuckTarget = hitTargetName
  if hitTargetName then
    events:emit("time_skip", { target = hitTargetName, amount = self.pendingAmount })
    FX.shockwave(ap.x, ap.y, ap.z, 12, 7, 0.3, 0.75, 1.0)
    fx:pulse(0.18)
    padVibrate(0.5, 0.3, 0.12)
  end
end

local function updateArrow(self, dt)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then return end

  if self.arrowFlying then
    local ap = arrowE.transform.position
    local nx, ny = ap.x + self.arrowVX * dt, ap.y + self.arrowVY * dt
    arrowE.transform.position = Vec3.new(nx, ny, ap.z)
    FX.trail(nx, ny, ap.z, 0.3, 0.75, 1.0)

    if tryReflect(self, arrowE, nx, ny) then return end

    local hitName = nil
    for _, name in ipairs(self.targetList) do
      local t = scene:findEntity(name)
      if t and t:isValid() then
        local tp, ts = t.transform.position, t.transform.scale
        if overlapAABB(nx, ny, self.arrowHalf, self.arrowHalf, tp.x, tp.y, ts.x * 0.5, ts.y * 0.5) then
          hitName = name
          break
        end
      end
    end

    local travelled = (nx - self.shotFromX) * (nx - self.shotFromX) + (ny - self.shotFromY) * (ny - self.shotFromY)
    if hitName then
      stickArrow(self, arrowE, hitName)
    elseif ny <= self.groundY + 0.12 then
      arrowE.transform.position = Vec3.new(nx, self.groundY + 0.12, ap.z)
      stickArrow(self, arrowE, nil)
    elseif travelled > self.arrowRange * self.arrowRange then
      stickArrow(self, arrowE, nil)
    end
    return
  end

  if self.arrowStuck then
    local p = self.transform.position
    local recovered = false
    if self.stuckTarget then
      -- 刺さった的自身に触れる(的が動いていれば矢もそれに追従して表示する)
      local t = scene:findEntity(self.stuckTarget)
      if t and t:isValid() then
        local tp, ts = t.transform.position, t.transform.scale
        arrowE.transform.position = Vec3.new(tp.x, tp.y, tp.z - 0.05)
        if overlapAABB(p.x, p.y, self.halfW, self.halfHeight, tp.x, tp.y, ts.x * 0.5, ts.y * 0.5) then
          recovered = true
        end
      else
        recovered = true  -- 的が消滅済みなら回収不能を回避し矢を返す
      end
    else
      if overlapAABB(p.x, p.y, self.halfW, self.halfHeight, self.stuckX, self.stuckY, self.arrowHalf, self.arrowHalf) then
        recovered = true
      end
    end
    if recovered then
      self.arrowStuck = false
      self.hasArrow = true
      self.stuckTarget = nil
      arrowE.transform.position = Vec3.new(0, -100, 0)
    end
  end
end

function OnUpdate(self, dt)
  -- 弓の発射表示時間を減らし、0未満にはしない。
  self.bowTimer = math.max(0, (self.bowTimer or 0) - dt)
  for name, t in pairs(self.ghostSolids) do
    self.ghostSolids[name] = t - dt
  end
  updateStandables(self, dt)
  updateMovement(self, dt)
  updateDraw(self, dt)
  updateArrow(self, dt)
  updatePlayerVisual(self)

  if keyPressed("ESC") or padPressed("START") then goToScene("scenes/title.json", 0.5) end
end
