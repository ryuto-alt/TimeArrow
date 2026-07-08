-- TimedDoor.lua -- 「閉まるドア・ゴール」= 本物の障害物。閉まっている間はPlayer.solids経由で
-- 物理的に通行不可(既定では死なない、ただ塞ぐだけ)。[openT, closeT) の間だけ沈んで通行可になる。
-- 矢で先送りすると窓へ滑り込ませられるが、引きすぎると窓を通り過ぎてまた閉まる
-- (=オーバーシュート。引き量の見極めがパズルになる)。listenButton=trueならボタンで開閉をトグルできる
-- (この場合 openT/closeT の時間窓は無視され、ボタン状態がそのまま開閉を決める)。
-- deadly=trueにすると閉状態への接触も即死にできる(トゲ付きゲート等、任意)。
properties = {
  { name = "openT",       type = "float", default = 8.0,  min = 0, max = 60, label = "開き始める時刻(秒)" },
  { name = "closeT",      type = "float", default = 11.0, min = 0, max = 60, label = "閉じる時刻(秒)" },
  { name = "sinkAmount",  type = "float", default = 2.6,  min = 0, max = 10, label = "開いた時に沈む量" },
  { name = "listenButton",type = "bool",  default = false,                   label = "ボタン連動(時間窓の代わりにボタンで開閉)" },
  { name = "deadly",      type = "bool",  default = false,                   label = "閉まってる間に触れると死ぬ(任意、既定は物理ブロックのみ)" },
  { name = "hitScale",    type = "float", default = 0.8,  min = 0.2, max = 1.5,label = "deadly時の当たり判定倍率" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0
  self.buttonOpen = false
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    -- 一括加算せず早送り(0.5秒で消化)して、開閉の動きが見えるようにする
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.bx, self.by, self.bz, 10, 0.3, 0.75, 1.0)
  end)

  events:on("button_toggle", function(data)
    if data.target ~= self.name or not self.listenButton then return end
    self.buttonOpen = not self.buttonOpen
  end)
end

function OnUpdate(self, dt)
  local open
  if self.listenButton then
    open = self.buttonOpen
  else
    self.clock = self.clock + dt
    if self.ffRemain > 0 then
      local step = math.min(self.ffRemain, self.ffSpeed * dt)
      self.clock = self.clock + step
      self.ffRemain = self.ffRemain - step
    end
    open = self.clock >= self.openT and self.clock < self.closeT
  end

  local y = open and (self.by - self.sinkAmount) or self.by
  self.transform.position = Vec3.new(self.bx, y, self.bz)

  -- 早送り中は半透明(=実体がない「経由中」の表現)
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    scene:setSpriteAlpha(selfE, self.ffRemain > 0 and 0.45 or 1.0)
  end

  -- 早送り中は途中経過なので即死判定しない(従来のワープと同じ扱い)
  if open or not self.deadly or self.ffRemain > 0 then return end
  local s = self.transform.scale
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp, ps = pl.transform.position, pl.transform.scale
  if overlapAABB(self.bx, self.by, s.x * 0.5 * self.hitScale, s.y * 0.5 * self.hitScale, pp.x, pp.y, ps.x * 0.5, ps.y * 0.5) then
    events:emit("player_died", {})
  end
end
