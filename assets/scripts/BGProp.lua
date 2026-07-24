-- BGProp.lua -- 背景装飾(BG_*モデル)のアイドル動作+時間消滅。
-- 歯車の回転・浮遊岩の上下はここで動かす(ギミックとは無関係の純装飾)。
-- T>0 なら「ステージ制限時間の全体を使って徐々に砕けて消える」進行度(0..1)を
-- BackdropLayer.hlsl へ毎フレーム送る(0秒で完全消滅)。
-- 弓の構え中(time_scaleイベント)は動きも消滅もスローになり、+10フラグで
-- シェーダーが青白い減彩に切り替わる(BackgroundCollapse.luaと同じ言語)。
properties = {
  { name = "spinZ",     type = "float", default = 0.0, min = -180, max = 180, label = "Z回転速度(度/秒, 歯車用)" },
  { name = "bobAmp",    type = "float", default = 0.0, min = 0,    max = 5,   label = "上下浮遊の振れ幅(浮遊岩用)" },
  { name = "bobAmpX",   type = "float", default = 0.0, min = 0,    max = 5,   label = "左右漂いの振れ幅(かけら用、上下と組で8の字)" },
  { name = "bobPeriod", type = "float", default = 9.0, min = 1,    max = 60,  label = "浮遊の周期(秒)" },
  { name = "phase",     type = "float", default = 0.0, min = 0,    max = 60,  label = "位相オフセット(秒)" },
  { name = "T",         type = "float", default = 0.0, min = 0,    max = 300, label = "ステージ制限時間(0=時間消滅なし)" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  local p = self.transform.position
  local r = self.transform.rotation
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.rx, self.ry = r.x, r.y
  self.spin = r.z
  self.clock = self.phase
  self.life = 0
  self.jump = 0        -- 先送り/後戻りでアニメ時計が消化すべき残量(±)
  self.slowSent = -1
  -- 消滅進行(life)は世界タイマーと同じ収支(GameManager.luaと同係数):
  -- 先送りで一気に砕け、後戻りの「返金」で砕けた分が再生する。
  -- 回転/浮遊のアニメ時計(self.clock)は見た目の演出なので、返金ではなく
  -- 「後戻り矢を撃った瞬間」に逆回転する(jump 経由で最大6倍速のスイープ消化)。
  -- ※返金でもjumpを動かすと後戻り対応ギミックで二重に戻ってしまうため分離
  events:on("time_skip", function(d)
    local a = (d.amount or 0) * 0.5
    self.life = self.life + a
    self.jump = self.jump + a
  end)
  events:on("time_rewind", function(d)
    local a = (d.amount or 0) * 0.35   -- GameManagerの即時返金と同係数
    self.life = math.max(0, self.life - a)
    self.jump = self.jump - a
  end)
end

function OnUpdate(self, dt)
  local rawDt = dt
  dt = dt * (self.ts or 1)
  self.clock = self.clock + dt
  self.life = self.life + dt
  -- 時間ジャンプの消化: 最大14倍速+2.2倍に誇張して回す(歯車がブオンと順/逆回転、
  -- 装飾なので時間の正確さより「時間が動いた」の視認性を優先)
  if self.jump ~= 0 then
    local step = clamp(self.jump, -rawDt * 14.0, rawDt * 14.0)
    self.clock = self.clock + step * 2.2
    self.jump = self.jump - step
    if math.abs(self.jump) < 0.001 then self.jump = 0 end
  end

  if self.spinZ ~= 0 then
    self.spin = (self.spin + self.spinZ * dt) % 360
    self.transform.rotation = Vec3.new(self.rx, self.ry, self.spin)
  end
  if self.bobAmp > 0 or self.bobAmpX > 0 then
    local w = (self.clock / self.bobPeriod) * math.pi * 2
    local ny = self.by + math.sin(w) * self.bobAmp
    -- 横は倍周期+位相ずれ=ゆったりした8の字を描く
    local nx = self.bx + math.sin(w * 0.5 + 1.7) * self.bobAmpX
    self.transform.position = Vec3.new(nx, ny, self.bz)
  end

  local slow = (self.ts or 1) < 1 and 10 or 0
  if self.T > 0 then
    -- 消滅進行度は毎フレーム送る(スローモーション中は進行も遅くなる)
    local frac = math.min(self.life / self.T, 1)
    local e = scene:findEntity(self.name)
    if e and e:isValid() then scene:setMeshEffect(e, frac + slow) end
    self.slowSent = -1
  elseif slow ~= self.slowSent then
    local e = scene:findEntity(self.name)
    if e and e:isValid() then
      scene:setMeshEffect(e, slow)
      self.slowSent = slow
    end
  end
end
