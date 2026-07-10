-- Arrow.lua
-- Arrow エンティティへこのスクリプトを付けた場合の自動回収補助。
-- 現在の Player スクリプトも矢を制御しているため、ここでは「刺さって静止した矢」を検出して戻す。

properties = {
  { name = "autoRecoverDelay", type = "float", default = 5.0, min = 0.0, max = 30, label = "自動回収開始までの秒数" },
  { name = "autoRecoverSpeed", type = "float", default = 18.0, min = 1.0, max = 60, label = "自動回収の速度" },
  { name = "recoverRadius", type = "float", default = 1.0, min = 0.1, max = 5, label = "自動回収完了距離" },
}

-- XY方向ベクトルを、矢モデルのZ回転角度へ変換する。
local function vectorToAngleDegrees(x, y)
  if math.atan2 then
    return math.deg(math.atan2(y, x))
  end

  -- Lua 5.1 など math.atan(y, x) がない環境でも四象限を保つ。
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

-- 矢の見た目を、プレイヤーへ戻る進行方向に合わせる。
local function setArrowDirection(self, x, y)
  if x == 0 and y == 0 then
    x = 1
    y = 0
  end

  self.transform.rotation = Vec3.new(0, 0, vectorToAngleDegrees(x, y))
end

function OnStart(self)
  local p = self.transform.position

  -- 静止時間を数えるため、前フレーム位置と自動帰還中フラグを保持する。
  self.lastX, self.lastY = p.x, p.y
  self.stillElapsed = 0
  self.returningToPlayer = false
end

function OnUpdate(self, dt)
  local player = scene:findEntity("Player")
  if not (player and player:isValid()) then
    return
  end

  local p = self.transform.position

  -- Player 側が矢を画面外へ隠している時は、回収済みとしてタイマーを戻す。
  if p.y < -50 then
    self.stillElapsed = 0
    self.returningToPlayer = false
    self.lastX, self.lastY = p.x, p.y
    return
  end

  local movedX = p.x - (self.lastX or p.x)
  local movedY = p.y - (self.lastY or p.y)
  local movedDistanceSq = movedX * movedX + movedY * movedY

  -- 飛行中など矢が動いている間は、刺さった時間として数えない。
  if movedDistanceSq > 0.000001 and not self.returningToPlayer then
    self.stillElapsed = 0
    self.lastX, self.lastY = p.x, p.y
    return
  end

  -- 静止している時間が指定秒数を超えるまでは、その場に刺さったままにする。
  self.stillElapsed = self.stillElapsed + dt
  if self.stillElapsed < self.autoRecoverDelay then
    self.lastX, self.lastY = p.x, p.y
    return
  end

  self.returningToPlayer = true

  local playerPosition = player.transform.position
  local dx = playerPosition.x - p.x
  local dy = playerPosition.y - p.y
  local distanceSq = dx * dx + dy * dy

  -- プレイヤー付近まで戻ったら、Player 側の回収判定に任せるためその場に置く。
  if distanceSq < self.recoverRadius * self.recoverRadius then
    self.lastX, self.lastY = p.x, p.y
    return
  end

  local distance = math.sqrt(distanceSq)
  if distance <= 0.0001 then
    self.lastX, self.lastY = p.x, p.y
    return
  end

  local dirX = dx / distance
  local dirY = dy / distance
  local moveDistance = self.autoRecoverSpeed * dt

  setArrowDirection(self, dirX, dirY)

  self.transform.position = Vec3.new(
    p.x + dirX * math.min(moveDistance, distance),
    p.y + dirY * math.min(moveDistance, distance),
    p.z)

  local nextPosition = self.transform.position
  self.lastX, self.lastY = nextPosition.x, nextPosition.y
end
