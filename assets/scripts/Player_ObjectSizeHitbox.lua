-- Player.lua
-- 時を先送りさせる矢：長押しで弓を引き、キーを離した瞬間に発射する。
--
-- キーボード:
--   L を長押し       : 弓を引く
--   L を押している間 : A/D/W/S または矢印キーで8方向に照準
--   L を離す         : 矢を発射
--
-- 弓を引いている間は、移動・ジャンプ・巻き戻し矢を使えない。
--
-- コントローラー:
--   RB を使用するための安全な呼び出し口を isControllerRBDown() に用意している。
--   このプロジェクトのゲームパッド入力API名が分かれば、そこだけ確定したAPI名へ置き換える。

local KeyCode = {
  A = KEY_A, B = KEY_B, C = KEY_C, D = KEY_D, E = KEY_E, F = KEY_F,
  G = KEY_G, H = KEY_H, I = KEY_I, J = KEY_J, K = KEY_K, L = KEY_L,
  M = KEY_M, N = KEY_N, O = KEY_O, P = KEY_P, Q = KEY_Q, R = KEY_R,
  S = KEY_S, T = KEY_T, U = KEY_U, V = KEY_V, W = KEY_W, X = KEY_X,
  Y = KEY_Y, Z = KEY_Z,
  SPACE = KEY_SPACE,
  ENTER = KEY_ENTER,
  UP = KEY_UP,
  DOWN = KEY_DOWN,
  LEFT = KEY_LEFT,
  RIGHT = KEY_RIGHT,
}

local function getKeyCode(keyName)
  if type(keyName) ~= "string" then return nil end
  local key = keyName:match("^%s*(.-)%s*$")
  if not key then return nil end
  return KeyCode[string.upper(key)]
end

-- properties の文字列キー名を KEY_* 定数へ変換して入力判定する。
-- KEY_* 定数は keyDown()/keyPressed() ではなく input:isKeyDown()/isKeyPressed() に渡す。
local function isKeyCodeDown(keyCode)
  return keyCode ~= nil and input:isKeyDown(keyCode)
end

local function isKeyCodePressed(keyCode)
  return keyCode ~= nil and input:isKeyPressed(keyCode)
end

local function isConfiguredKeyDown(keyName)
  return isKeyCodeDown(getKeyCode(keyName))
end

local function isConfiguredKeyPressed(keyName)
  return isKeyCodePressed(getKeyCode(keyName))
end

properties = {
  { name = "speed",        type = "float",  default = 6.0,  min = 1,  max = 15, label = "移動速度" },
  { name = "jumpSpeed",    type = "float",  default = 9.5,  min = 1,  max = 20, label = "ジャンプ初速" },
  { name = "gravity",      type = "float",  default = 22.0, min = 1,  max = 60, label = "重力加速度" },
  { name = "groundY",      type = "float",  default = 0.0,                     label = "地面のY" },
  { name = "halfHeight",   type = "float",  default = 0.8,  min = 0.1, max = 3, label = "スプライト半分の高さ(接地オフセット)" },

  { name = "arrowSpeed",   type = "float",  default = 14.0, min = 1,  max = 40, label = "矢の速度" },
  { name = "arrowRange",   type = "float",  default = 16.0, min = 1,  max = 60, label = "矢の最大飛距離" },

  -- 命中対象側の hitBoxSize × Transform Scale が実際の判定サイズになる。
  -- これは矢自体の太さだけを追加するための半径。
  { name = "arrowHitRadius", type = "float", default = 0.08, min = 0.0, max = 1, label = "矢の太さ(判定の余白)" },
  { name = "fallbackHitWidth",  type = "float", default = 1.0, min = 0.1, max = 20, label = "未登録対象の判定横幅" },
  { name = "fallbackHitHeight", type = "float", default = 1.0, min = 0.1, max = 20, label = "未登録対象の判定縦幅" },

  { name = "recoverRadius",type = "float",  default = 1.0,  min = 0.1, max = 5, label = "矢の回収判定半径" },
  { name = "autoRecoverDelay", type = "float", default = 5.0, min = 0.0, max = 30, label = "自動回収開始までの秒数" },
  { name = "autoRecoverSpeed", type = "float", default = 18.0, min = 1.0, max = 60, label = "自動回収の速度" },
  { name = "skipAmount",   type = "float",  default = 1.0,  min = 0,  max = 10, label = "先送り/巻き戻し量" },
  { name = "canRewind",    type = "bool",   default = false,                   label = "巻き戻し矢を使えるか" },

  -- 入力設定: インスペクターでは "A" や "L" のように入力する。
  -- getKeyCode() が KEY_A / KEY_L などのキー定数へ変換する。
  { name = "drawKey",      type = "string", default = "L",                     label = "弓を引くキー" },
  { name = "rewindKey",    type = "string", default = "Q",                     label = "巻き戻し矢キー" },
  { name = "moveLeftKey",  type = "string", default = "A",                     label = "左移動・左照準キー" },
  { name = "moveRightKey", type = "string", default = "D",                     label = "右移動・右照準キー" },
  { name = "moveUpKey",    type = "string", default = "W",                     label = "上照準キー" },
  { name = "moveDownKey",  type = "string", default = "S",                     label = "下照準キー" },
  { name = "jumpKey",      type = "string", default = "SPACE",                 label = "ジャンプキー" },
  { name = "showInputDebug", type = "bool", default = true,                    label = "入力確認表示を出す" },

  -- 旧データ互換用。新しい命中対象は TimeObject / FiexdObject タグ付きの通知から自動登録する。
  { name = "targets",      type = "string", default = "",                      label = "旧:時間を動かす対象(カンマ区切り)" },
  { name = "fixedTargets", type = "string", default = "",                      label = "旧:矢が刺さる固定対象(カンマ区切り)" },

  { name = "camOffsetX",   type = "float",  default = 0.0,                     label = "カメラXオフセット" },
  { name = "camOffsetY",   type = "float",  default = 2.5,                     label = "カメラYオフセット" },
  { name = "camOffsetZ",   type = "float",  default = -13.0,                   label = "カメラZオフセット" },
}

local function trimSplit(csv)
  local out = {}
  for w in string.gmatch(csv or "", "[^,]+") do
    local name = w:match("^%s*(.-)%s*$")
    if name ~= "" then
      out[#out + 1] = name
    end
  end
  return out
end

-- 未対応のゲームパッド関数を呼んでエラーにしないための補助。
local function tryOptionalInputFunction(functionName, ...)
  local fn = rawget(_G, functionName)
  if type(fn) ~= "function" then
    return false
  end

  local ok, result = pcall(fn, ...)
  return ok and result == true
end

-- エンジンが次のどれかの入力APIを持っていればRBを使える。
-- API_REFERENCE.md が分かれば、実際に存在する1つだけを残すのが確実。
local function isControllerRBDown()
  return tryOptionalInputFunction("gamepadButtonDown", "RB")
      or tryOptionalInputFunction("controllerButtonDown", "RB")
      or tryOptionalInputFunction("padButtonDown", "RB")
end

-- properties の「弓を引くキー」、または対応している場合はコントローラーRBを押し続けているか。
local function isDrawButtonDown(self)
  return isConfiguredKeyDown(self.drawKey) or isControllerRBDown()
end

-- 通常時は移動入力、弓を引いている間は照準入力として使う。
-- 戻り値は正規化済みの8方向ベクトル。入力がなければ nil。
local function getAimInput(self)
  local x, y = 0, 0

  if isConfiguredKeyDown(self.moveLeftKey) or isKeyCodeDown(KeyCode.LEFT) then
    x = x - 1
  end
  if isConfiguredKeyDown(self.moveRightKey) or isKeyCodeDown(KeyCode.RIGHT) then
    x = x + 1
  end
  if isConfiguredKeyDown(self.moveUpKey) or isKeyCodeDown(KeyCode.UP) then
    y = y + 1
  end
  if isConfiguredKeyDown(self.moveDownKey) or isKeyCodeDown(KeyCode.DOWN) then
    y = y - 1
  end

  if x == 0 and y == 0 then
    return nil, nil
  end

  -- 斜め方向も上下左右と同じ速さになるように正規化する。
  local length = math.sqrt(x * x + y * y)
  return x / length, y / length
end

local function aimDirectionText(x, y)
  if y > 0.5 then
    if x > 0.5 then return "UP-RIGHT" end
    if x < -0.5 then return "UP-LEFT" end
    return "UP"
  end

  if y < -0.5 then
    if x > 0.5 then return "DOWN-RIGHT" end
    if x < -0.5 then return "DOWN-LEFT" end
    return "DOWN"
  end

  if x < 0 then return "LEFT" end
  return "RIGHT"
end

-- Lua 5.1系では math.atan2、Lua 5.3以降では math.atan(y, x) を使うため、
-- エンジン側のLuaバージョン差を吸収してXY方向ベクトルの角度を度数で返す。
local function vectorToAngleDegrees(x, y)
  if math.atan2 then
    return math.deg(math.atan2(y, x))
  end

  -- math.atan(y, x) 非対応のLuaでも左右反転と上下方向を正しく扱う。
  if x > 0 then
    return math.deg(math.atan(y / x))
  end
  if x < 0 and y >= 0 then
    return math.deg(math.atan(y / x)) + 180
  end
  if x < 0 and y < 0 then
    return math.deg(math.atan(y / x)) - 180
  end
  if y > 0 then
    return 90
  end
  if y < 0 then
    return -90
  end

  return 0
end

-- 矢モデルはローカルX方向が長さ方向なので、XY平面の発射方向に合わせてZ回転する。
-- aimX/aimY や arrowVX/arrowVY と同じ向きを渡せば、構え中・飛行中・刺さった後の見た目が揃う。
local function setArrowDirection(arrowE, x, y)
  if not (arrowE and arrowE:isValid()) then
    return
  end

  -- ゼロベクトルでは角度が決まらないため、入力がない場合は右向きに戻す。
  if x == 0 and y == 0 then
    x = 1
    y = 0
  end

  arrowE.transform.rotation = Vec3.new(0, 0, vectorToAngleDegrees(x, y))
end

function OnStart(self)
  local p = self.transform.position
  self.startX, self.startY, self.startZ = p.x, p.y, p.z

  self.vx, self.vy = 0, 0
  self.facing = 1
  self.grounded = false

  self.hasArrow = true
  self.arrowFlying = false
  self.arrowStuck = false
  self.arrowVX, self.arrowVY = 0, 0
  self.arrowDir = 1
  self.stuckX, self.stuckY = 0, 0
  self.stuckElapsed = 0
  self.arrowReturning = false
  self.shotFromX, self.shotFromY = 0, 0

  -- 弓を引いている状態と、現在の照準方向。
  self.isDrawing = false
  self.aimX, self.aimY = 1, 0

  -- 矢の命中対象リスト。新仕様では名前指定ではなく、各対象が送るタグ付き通知で自動登録する。
  self.targetList = {}
  local registeredTargetNames = {}

  -- TimeObject / FiexdObject が毎フレーム送る矩形当たり判定情報。
  -- 送信側より先に Player が開始した場合でも、次フレーム以降に必ず更新される。
  self.targetBounds = {}
  events:on("arrow_target_bounds", function(data)
    if type(data) ~= "table" or type(data.target) ~= "string" then
      return
    end

    -- 初めて届いたタグ付き対象だけを命中判定リストへ追加する。
    if not registeredTargetNames[data.target] then
      registeredTargetNames[data.target] = true
      self.targetList[#self.targetList + 1] = data.target
    end

    self.targetBounds[data.target] = {
      x = data.x,
      y = data.y,
      width = data.width,
      height = data.height,
      tag = data.tag,
    }
  end)

  if p.y < self.groundY + self.halfHeight then
    self.transform.position = Vec3.new(p.x, self.groundY + self.halfHeight, p.z)
    self.startY = self.groundY + self.halfHeight
  end

  local arrowE = scene:findEntity("Arrow")
  if arrowE and arrowE:isValid() then
    arrowE.transform.position = Vec3.new(0, -100, 0)
    setArrowDirection(arrowE, 1, 0)
    scene:setColor(arrowE, 1.0, 0.35, 0.1)
  end

  events:on("player_died", function(data)
    self.respawnPending = true
  end)
end

local function respawn(self)
  self.transform.position = Vec3.new(self.startX, self.startY, self.startZ)
  self.vx, self.vy = 0, 0
  self.isDrawing = false
  self.respawnPending = false
end

-- L/RBを押している間、照準方向を更新する。
-- trueを返したフレームは「離した瞬間」なので、その後に発射する。
local function updateDrawState(self)
  self.releasedDrawButton = false

  -- 矢を失っている間は弓を引けない。
  if not self.hasArrow or self.arrowFlying or self.arrowStuck then
    self.isDrawing = false
    return
  end

  if isDrawButtonDown(self) then
    self.isDrawing = true

    local inputX, inputY = getAimInput(self)
    if inputX ~= nil then
      self.aimX, self.aimY = inputX, inputY

      -- 横入力があったときだけキャラクターの左右向きも更新する。
      if inputX > 0.1 then
        self.facing = 1
      elseif inputX < -0.1 then
        self.facing = -1
      end
    end
    return
  end

  -- 前フレームまで弓を引いていて、今フレームではボタンが離されている。
  if self.isDrawing then
    self.isDrawing = false
    self.releasedDrawButton = true
  end
end

local function updateMovement(self, dt)
  local move = 0

  -- 弓を引いている間は、移動・ジャンプ入力を完全に受け付けない。
  if not self.isDrawing then
    if isConfiguredKeyDown(self.moveLeftKey) or isKeyCodeDown(KeyCode.LEFT) then
      move = move - 1
    end
    if isConfiguredKeyDown(self.moveRightKey) or isKeyCodeDown(KeyCode.RIGHT) then
      move = move + 1
    end

    if move ~= 0 then
      self.facing = move
    end

    if self.grounded and isConfiguredKeyPressed(self.jumpKey) then
      self.vy = self.jumpSpeed
      self.grounded = false
    end
  end

  self.vx = move * self.speed

  -- 弓を引き始めた瞬間に空中で止まり続けないよう、重力だけは常に適用する。
  self.vy = self.vy - self.gravity * dt

  local p = self.transform.position
  local nx = p.x + self.vx * dt
  local ny = p.y + self.vy * dt

  local restY = self.groundY + self.halfHeight
  if ny <= restY then
    ny = restY
    self.vy = 0
    self.grounded = true
  else
    self.grounded = false
  end

  self.transform.position = Vec3.new(nx, ny, p.z)
  self.transform.rotation = Vec3.new(0, self.facing < 0 and 180 or 0, 0)

  if ny < -8 then
    respawn(self)
  end
end

local function launchArrow(self, timeDirection)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then
    return
  end

  local p = self.transform.position
  arrowE.transform.position = Vec3.new(
    p.x + self.aimX * 0.7,
    p.y + self.aimY * 0.7 + 0.2,
    p.z)
  setArrowDirection(arrowE, self.aimX, self.aimY)

  self.hasArrow = false
  self.arrowFlying = true
  self.arrowDir = timeDirection
  self.arrowVX = self.aimX * self.arrowSpeed
  self.arrowVY = self.aimY * self.arrowSpeed
  self.shotFromX = p.x
  self.shotFromY = p.y + 0.2
end

local function updateShooting(self)
  -- L/RBを離した瞬間に先送り矢を撃つ。
  if self.releasedDrawButton then
    launchArrow(self, 1)
    return
  end

  -- 巻き戻し矢は弓を引いている間には使用できない。
  -- 現在の仕様を残すため、canRewind が有効なときだけ Q で撃てる。
  if not self.isDrawing
    and self.canRewind
    and self.hasArrow
    and not self.arrowFlying
    and not self.arrowStuck
    and isConfiguredKeyPressed(self.rewindKey) then
    self.aimX, self.aimY = self.facing, 0
    launchArrow(self, -1)
  end
end

local function stickArrow(self, arrowE, hitTargetName)
  local ap = arrowE.transform.position
  self.arrowFlying = false
  self.arrowStuck = true
  self.stuckX, self.stuckY = ap.x, ap.y
  self.stuckElapsed = 0
  self.arrowReturning = false

  if hitTargetName then
    -- 時間を動かす/動かさないに関係なく、矢が当たった事実を対象へ通知する。
    events:emit("arrow_hit", {
      target = hitTargetName,
      dir = self.arrowDir,
      amount = self.skipAmount,
    })

    local bounds = self.targetBounds[hitTargetName]
    local targetTag = bounds and bounds.tag or nil

    -- TimeObject タグだけに時間操作イベントを送る。FiexdObject タグは矢が刺さるだけで動かさない。
    if targetTag == "TimeObject" then
      events:emit("time_skip", {
        target = hitTargetName,
        dir = self.arrowDir,
        amount = self.skipAmount,
      })
    end
  end
end

-- 矢を所持状態へ戻し、見えない位置へ退避させる。
local function recoverArrow(self, arrowE)
  self.arrowStuck = false
  self.arrowReturning = false
  self.stuckElapsed = 0
  self.hasArrow = true
  arrowE.transform.position = Vec3.new(0, -100, 0)
  setArrowDirection(arrowE, 1, 0)
end

-- 刺さった矢が一定時間回収されなかった場合、プレイヤーへ向かって戻す。
local function updateArrowAutoRecover(self, arrowE, dt)
  local playerPosition = self.transform.position
  local arrowPosition = arrowE.transform.position
  local dx = playerPosition.x - arrowPosition.x
  local dy = playerPosition.y - arrowPosition.y
  local distanceSq = dx * dx + dy * dy
  local recoverRadiusSq = self.recoverRadius * self.recoverRadius

  -- プレイヤーが通常回収範囲に入ったら即座に回収する。
  if distanceSq < recoverRadiusSq then
    recoverArrow(self, arrowE)
    return
  end

  -- 刺さってからの経過時間を数え、指定秒数を超えるまではその場に残す。
  self.stuckElapsed = self.stuckElapsed + dt
  if self.stuckElapsed < self.autoRecoverDelay then
    return
  end

  self.arrowReturning = true

  -- プレイヤー方向へ正規化して移動させ、見た目の向きも進行方向へ合わせる。
  local distance = math.sqrt(distanceSq)
  if distance <= 0.0001 then
    recoverArrow(self, arrowE)
    return
  end

  local moveDistance = self.autoRecoverSpeed * dt
  local dirX = dx / distance
  local dirY = dy / distance
  setArrowDirection(arrowE, dirX, dirY)

  if moveDistance >= distance then
    recoverArrow(self, arrowE)
    return
  end

  arrowE.transform.position = Vec3.new(
    arrowPosition.x + dirX * moveDistance,
    arrowPosition.y + dirY * moveDistance,
    arrowPosition.z)
end

-- 直線で飛ぶ矢と、軸に平行な矩形(AABB)の交差位置を返す。
-- 返り値は 0.0〜1.0 の線分上の位置。命中しない場合は nil。
local function segmentVsAabb(x0, y0, x1, y1, minX, maxX, minY, maxY)
  local dx = x1 - x0
  local dy = y1 - y0
  local enterT = 0.0
  local exitT = 1.0
  local epsilon = 0.000001

  local function testAxis(origin, delta, minimum, maximum)
    if math.abs(delta) < epsilon then
      return origin >= minimum and origin <= maximum
    end

    local t1 = (minimum - origin) / delta
    local t2 = (maximum - origin) / delta
    if t1 > t2 then
      t1, t2 = t2, t1
    end

    if t1 > enterT then enterT = t1 end
    if t2 < exitT then exitT = t2 end
    return enterT <= exitT
  end

  if not testAxis(x0, dx, minX, maxX) then return nil end
  if not testAxis(y0, dy, minY, maxY) then return nil end
  return enterT
end

-- targetBounds がまだ届いていない1フレーム目だけに使う保険。
-- Transform Scale を読める場合は、それも横幅・縦幅へ反映する。
local function getFallbackBounds(self, target)
  local p = target.transform.position
  local width = self.fallbackHitWidth
  local height = self.fallbackHitHeight

  local ok, scale = pcall(function()
    return target.transform.scale
  end)

  if ok and scale then
    local sx = math.abs(scale.x or 1.0)
    local sy = math.abs(scale.y or 1.0)
    if sx > 0.0001 then width = width * sx end
    if sy > 0.0001 then height = height * sy end
  end

  return p.x, p.y, width, height
end

local function updateArrow(self, dt)
  local arrowE = scene:findEntity("Arrow")
  if not (arrowE and arrowE:isValid()) then
    return
  end

  -- 弓を引いている間は、矢をプレイヤーの前に表示する。
  if self.isDrawing and self.hasArrow then
    local p = self.transform.position
    arrowE.transform.position = Vec3.new(
      p.x + self.aimX * 0.7,
      p.y + self.aimY * 0.7 + 0.2,
      p.z)
    setArrowDirection(arrowE, self.aimX, self.aimY)
    return
  end

  if self.arrowFlying then
    local ap = arrowE.transform.position
    local nx = ap.x + self.arrowVX * dt
    local ny = ap.y + self.arrowVY * dt
    setArrowDirection(arrowE, self.arrowVX, self.arrowVY)

    -- 1フレーム内で複数の対象を横切る場合、矢に最初に当たる対象を選ぶ。
    local nearestHitT = nil
    local hitName = nil

    for _, name in ipairs(self.targetList) do
      local target = scene:findEntity(name)
      if target and target:isValid() then
        local bounds = self.targetBounds[name]
        local centerX, centerY, width, height

        if bounds
          and type(bounds.x) == "number"
          and type(bounds.y) == "number"
          and type(bounds.width) == "number"
          and type(bounds.height) == "number" then
          centerX = bounds.x
          centerY = bounds.y
          width = bounds.width
          height = bounds.height
        else
          centerX, centerY, width, height = getFallbackBounds(self, target)
        end

        -- 矢の太さ分だけ矩形を外側へ広げる。
        local halfWidth = math.max(width * 0.5, 0.01) + self.arrowHitRadius
        local halfHeight = math.max(height * 0.5, 0.01) + self.arrowHitRadius

        local hitT = segmentVsAabb(
          ap.x, ap.y, nx, ny,
          centerX - halfWidth, centerX + halfWidth,
          centerY - halfHeight, centerY + halfHeight)

        if hitT and (nearestHitT == nil or hitT < nearestHitT) then
          nearestHitT = hitT
          hitName = name
        end
      end
    end

    if hitName then
      -- 矢を物体の表面へ戻してから刺す。
      local hitX = ap.x + (nx - ap.x) * nearestHitT
      local hitY = ap.y + (ny - ap.y) * nearestHitT
      arrowE.transform.position = Vec3.new(hitX, hitY, ap.z)
      stickArrow(self, arrowE, hitName)
    else
      arrowE.transform.position = Vec3.new(nx, ny, ap.z)

      local dx = nx - self.shotFromX
      local dy = ny - self.shotFromY
      if dx * dx + dy * dy > self.arrowRange * self.arrowRange then
        stickArrow(self, arrowE, nil)
      end
    end
    return
  end

  if self.arrowStuck then
    updateArrowAutoRecover(self, arrowE, dt)
  end
end

local function updateCamera(self)
  local cam = scene:findEntity("GameCamera")
  if cam and cam:isValid() then
    local p = self.transform.position
    cam.transform.position = Vec3.new(
      p.x + self.camOffsetX,
      p.y + self.camOffsetY,
      p.z + self.camOffsetZ)
  end
end

function OnUpdate(self, dt)
  if self.respawnPending then
    respawn(self)
  end

  -- 先に弓状態を更新することで、Lを押したそのフレームから移動を止める。
  updateDrawState(self)
  updateMovement(self, dt)
  updateShooting(self)
  updateArrow(self, dt)
  updateCamera(self)

  local arrowState
  if self.isDrawing then
    arrowState = "DRAWING"
  elseif self.hasArrow then
    arrowState = "READY"
  elseif self.arrowFlying then
    arrowState = "FLYING"
  elseif self.arrowReturning then
    arrowState = "RETURNING"
  else
    arrowState = "STUCK (touch it to recover)"
  end

  ui:text(20, 20, "Arrow: " .. arrowState, 22, 1, 1, 1, 1)
  ui:text(20, 48, "Hold " .. string.upper(self.drawKey or "") .. ": Draw / Release: Fire", 18, 0.85, 0.9, 1, 1)

  -- drawKey の設定値と、実際に input API がキーを検出しているかを確認できる。
  if self.showInputDebug then
    local drawKeyCode = getKeyCode(self.drawKey)
    local drawKeyState = isKeyCodeDown(drawKeyCode) and "DOWN" or "UP"
    local drawKeyName = string.upper(self.drawKey or "")
    if drawKeyCode == nil then
      drawKeyName = drawKeyName .. " (INVALID)"
    end
    ui:text(20, 76, "Draw Key: " .. drawKeyName .. " / " .. drawKeyState, 18, 0.3, 1, 0.45, 1)
  end

  if self.isDrawing then
    ui:text(20, self.showInputDebug and 104 or 76, "Aim: " .. aimDirectionText(self.aimX, self.aimY), 18, 1, 0.85, 0.3, 1)
  end

  if keyPressed("ESC") then
    goToScene("scenes/title.json", 0.5)
  end
end
