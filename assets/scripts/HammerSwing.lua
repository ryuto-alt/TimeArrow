-- HammerSwing.lua -- ゼンマイ仕掛けの振り子ハンマー(Hammer_Pendulum、原点=支点)。
-- 時間が経つほどゼンマイがほどけて振りが【遅く】なる(周期が伸びる)= 時間に実体がある。
--   先送り矢: 一気に老化 → 振りが鈍って安全窓が広がる=悠々と下を通れる(無力化の正解)
--   後戻し矢: ゼンマイが巻き戻って若返り、鋭い振りに戻る(+実効量の返金=銀行にもなる)
-- 直線ノコと違い、通路を塞ぐのは振り下ろしの一瞬だけ=タイミングで渡れる。
properties = {
  { name = "period",     type = "float", default = 3.2, min = 0.8, max = 12, label = "若い時の振り周期(秒)" },
  { name = "maxAngle",   type = "float", default = 55.0, min = 10, max = 85, label = "最大振り角(度)" },
  { name = "startPhase", type = "float", default = 0.0, min = 0,   max = 60, label = "開始時の年齢(秒)" },
  { name = "decayT",     type = "float", default = 25.0, min = 5,  max = 120,label = "この年齢で周期が2倍に伸びる(老化速度)" },
  { name = "hitHalf",    type = "float", default = 0.42, min = 0.2, max = 2, label = "ヘッドの当たり半径" },
  { name = "agePerSkip", type = "float", default = 9.4, min = 1, max = 30, label = "矢1秒あたりの老化年数(合計8秒スキップ=75歳でチリ化)" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  events:on("aim_preview", function(d)
    if d.target == self.name or d.target == self.name .. "X" then
      self.aimPv = { m = d.mode, t = 0.12 }
    end
  end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = self.startPhase
  self.phase = 0            -- 振りの位相。周期が年齢で変わるため別積分
  self.ffRemain = 0

  -- 崩壊時に飛び散る実体破片(シーンに事前配置された自名+"_f1..f12"。無ければ火花のみ)
  self.frags = {}
  for i = 1, 12 do
    local fe = scene:findEntity(self.name .. "_f" .. i)
    if fe and fe:isValid() then self.frags[#self.frags + 1] = fe end
  end
  -- 復活演出用の時の結晶(自名+"_t1..t6")
  self.shards = {}
  for i = 1, 6 do
    local se = scene:findEntity(self.name .. "_t" .. i)
    if se and se:isValid() then self.shards[#self.shards + 1] = se end
  end

  -- 矢の秒数は agePerSkip 倍の「年齢」に換算(5秒スキップ=+25歳: 新品→摩耗、もう1発で錆)
  events:on("time_skip", function(data)
    if data.target ~= self.name and data.target ~= self.name .. "X" then return end
    self.ffRemain = self.ffRemain + (data.amount or 0) * self.agePerSkip
    self.ffSpeed = self.ffRemain / 1.5   -- 1.5秒かけて老化が進む(全ギミック共通の消化テンポ。早送り中は無害)
    FX.spark(self.bx, self.by, self.bz, 10, 0.3, 0.75, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.3, 0.9, 1.0)
  end)

  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name and data.target ~= self.name .. "X" then return end
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0) * self.agePerSkip
    self.rwSpeed = self.rwRemain / 1.5   -- FFと同じ1.5秒消化(全ギミック統一テンポ。RWだけ3倍速で落下が速すぎた)
    self.rwGlow = 0.1
    FX.spark(self.bx, self.by, self.bz, 12, 0.65, 0.4, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.65, 0.4, 1.0)
  end)
end

-- 年齢→現在の周期(老いるほど遅い)。decayT歳で2倍、最大4倍まで伸びる
local function currentPeriod(self)
  local stretch = math.min(4.0, 1.0 + self.clock / self.decayT)
  return self.period * stretch
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)
  local before = self.clock
  self.clock = self.clock + dt
  if self.ffRemain > 0 then
    local step = math.min(self.ffRemain, self.ffSpeed * dt)
    self.clock = self.clock + step
    self.ffRemain = self.ffRemain - step
  end
  if self.rwRemain and self.rwRemain > 0 then
    local step = math.min(self.rwRemain, self.rwSpeed * dt, self.clock)
    if step <= 0 then
      self.rwRemain = 0
    else
      self.clock = self.clock - step
      self.rwRemain = self.rwRemain - step
      self.rwGlow = 0.1
      -- 返金は矢の実秒数ぶんだけ(年齢換算の逆変換。倍率ぶん得する銀行にはしない)
      events:emit("time_refund", { amount = step / self.agePerSkip })
    end
  end

  -- チリ化年齢(decayT×3)で時計を止める=それ以上は風化せず、後戻り矢が常に即効く
  local dustAge = self.decayT * 3.0
  if self.clock > dustAge then self.clock = dustAge end

  -- 位相は「その瞬間の周期」で進める(年齢が変わると振りの速さが目に見えて変わる)。
  -- 復活シーケンス中と直後1秒(swingHold)は振り子を止めておき、その後に再開する
  if self.reviveFx or (self.swingHold or 0) > 0 then
    self.swingHold = math.max(0, (self.swingHold or 0) - dt)
  else
    local dClock = self.clock - before
    self.phase = self.phase + dClock / currentPeriod(self)
  end
  local ang = self.maxAngle * math.sin(self.phase * math.pi * 2)
  self.transform.rotation = Vec3.new(0, 0, ang)

  -- 経年劣化の見た目: 新品(〜0.8×decayT) / 摩耗(〜2×decayT) / 錆(それ以上)。
  -- FF/RWで年齢が動くとモデルも入れ替わる=時間操作が見た目で分かる
  local R = 2.35 * self.transform.scale.y
  local groundY = self.by - R - 0.55 * self.transform.scale.y
  local m2 = scene:findEntity(self.name .. "_m2")
  local m3 = scene:findEntity(self.name .. "_m3")
  local m4 = scene:findEntity(self.name .. "_m4")
  if m2 and m2:isValid() and m3 and m3:isValid() then
    local stage = (self.clock < self.decayT * 0.8) and 1 or
                  ((self.clock < self.decayT * 2.0) and 2 or
                  ((self.clock < dustAge) and 3 or 4))
    -- 段階が変わった瞬間: 破片が弾けるフラッシュ(劣化/若返りの節目を見せる)
    if self.lastStage and stage ~= self.lastStage then
      local hy0 = self.by - 2.35 * self.transform.scale.y
      FX.shockwave(self.bx, hy0, self.bz, 14, 9, 0.75, 0.5, 0.3)
      FX.spark(self.bx, hy0, self.bz, 18, 0.6, 0.4, 0.25)
      fx:pulse(0.15)
      if stage == 4 then                      -- 崩壊: 豪快に弾けてチリの山へ
        -- 三重の衝撃波+上下2段の大量火花+粉塵。画面も大きく揺らす
        audio:playSpatial("audio/se/crush.wav", self.bx, groundY + 0.5, self.bz, 4, 30, 1.0)
        FX.spark(self.bx, groundY + 0.4, self.bz, 60, 0.6, 0.55, 0.45)
        FX.spark(self.bx, groundY + 1.4, self.bz, 50, 1.0, 0.75, 0.3)
        FX.spark(self.bx, groundY + 0.2, self.bz, 40, 0.85, 0.8, 0.7)
        FX.shockwave(self.bx, groundY + 0.5, self.bz, 26, 16, 0.62, 0.58, 0.5)
        FX.shockwave(self.bx, groundY + 0.5, self.bz, 14, 22, 1.0, 0.8, 0.4)
        FX.shockwave(self.bx, self.by - R * 0.5, self.bz, 20, 10, 0.9, 0.6, 0.3)
        fx:pulse(0.5)
        -- 実体破片パーティクル: 鉄チャンクと木の裂片が高速で豪快に弾け飛ぶ
        self.fragFx = {}
        for k, fe in ipairs(self.frags) do
          local a = math.rad(20 + math.random() * 140)   -- ほぼ全方位上向きにばらまく
          local sp = 7.0 + math.random() * 6.5
          self.fragFx[k] = { e = fe,
            x = self.bx + (math.random() - 0.5) * 1.2,
            y = groundY + 0.7 + math.random() * 1.2,
            vx = math.cos(a) * sp, vy = math.sin(a) * sp + 2.0,
            rot = math.random() * 360, spin = (math.random() - 0.5) * 1600, t = 0 }
        end
      elseif self.lastStage == 4 then         -- 後戻りで復活: 逆再生の再構築シーケンス開始
        -- 破片が四方から吸い込まれて集まり、時の結晶が渦を巻く。合体までモデルは隠す
        self.fragFx = nil                     -- 崩壊アニメが残っていたら打ち切り
        self.reviveFx = { t = 0, dur = 1.1, list = {}, shards = {} }
        local cy = self.by - R * 0.6
        for k, fe in ipairs(self.frags) do
          local a = math.random() * math.pi * 2
          local r = 2.5 + math.random() * 2.5
          self.reviveFx.list[k] = { e = fe,
            sx = self.bx + math.cos(a) * r,
            sy = math.max(groundY + 0.15, cy + math.sin(a) * r),
            rot = math.random() * 360, spin = (math.random() - 0.5) * 1200,
            delay = math.random() * 0.25 }
        end
        for k, se in ipairs(self.shards) do
          self.reviveFx.shards[k] = { e = se, a0 = math.random() * math.pi * 2,
            r0 = 3.2 + math.random() * 1.5, rot = math.random() * 360 }
        end
        FX.shockwave(self.bx, cy, self.bz, 12, 8, 0.65, 0.4, 1.0)
        fx:pulse(0.15)
      end
    end
    self.lastStage = stage
    -- 復活シーケンス中は全モデルを隠す(破片が集まりきった瞬間に現れる)
    local hideAll = self.reviveFx ~= nil
    local ents = { scene:findEntity(self.name), m2, m3, m4 }
    for i, e in ipairs(ents) do
      if e and e:isValid() then
        if i == 1 then
          -- 本体(判定/イベント持ち)は常に支点に置く。新品段階以外は見た目だけ隠す…はできないので
          -- 本体=新品モデル。段階2/3では本体を奥へ僅かに引っ込め、該当モデルを支点へ出す
          local show = (stage == 1) and not hideAll
          e.transform.position = Vec3.new(self.bx, show and self.by or -100, self.bz)
        elseif i == 4 then
          -- チリ(第4段階): 振り子の真下の床に残骸の山として置く。触れても安全。
          -- ピンク発光=「後戻り矢で呼び戻せ」の示唆。復活は time_rewind で時計が戻るだけ
          local show = (stage == 4) and not hideAll
          e.transform.position = Vec3.new(self.bx, show and groundY or -100, self.bz)
          e.transform.rotation = Vec3.new(0, 0, 0)
          if show then
            local eff = 11.5
            if self.rwGlow > 0 then eff = 2.8 end
            if self.aimPv and self.aimPv.t > 0 then
              eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
            end
            scene:setMeshEffect(e, eff)
          end
        else
          local show = (stage == i) and not hideAll
          e.transform.position = Vec3.new(self.bx, show and self.by or -100, self.bz)
          e.transform.rotation = Vec3.new(0, 0, ang)
          if show then
            local eff = 6.0 + math.min(0.95, self.clock / (self.decayT * 2.5))
            if self.ffRemain > 0 then eff = 1.0
            elseif self.rwGlow > 0 then eff = 2.8 end
            if self.aimPv and self.aimPv.t > 0 then
              eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
            end
            scene:setMeshEffect(e, eff)
          end
        end
      end
    end
  end

  -- 復活アニメ: 破片が四方から吸い込まれ、時の結晶が渦を巻いて集まり、合体して閃光
  if self.reviveFx then
    local rv = self.reviveFx
    rv.t = rv.t + dt
    local cy = self.by - R * 0.6
    local done = rv.t >= rv.dur
    for _, f in ipairs(rv.list) do
      if f.e and f.e:isValid() then
        local u = clamp((rv.t - f.delay) / math.max(rv.dur - 0.2 - f.delay, 0.1), 0, 1)
        u = u * u * (3 - 2 * u)                 -- smoothstep: 加速して吸い込まれる
        local x = f.sx + (self.bx - f.sx) * u
        local y = f.sy + (cy - f.sy) * u
        f.rot = f.rot + f.spin * dt
        if done or u >= 1 then
          f.e.transform.position = Vec3.new(x, -100, self.bz)
        else
          f.e.transform.position = Vec3.new(x, y, self.bz - 0.1)
          f.e.transform.rotation = Vec3.new(0, 0, f.rot % 360)
          if math.random() < 0.6 then FX.trail(x, y, self.bz, 0.65, 0.4, 1.0) end
        end
      end
    end
    for _, s in ipairs(rv.shards) do
      if s.e and s.e:isValid() then
        local u = clamp(rv.t / rv.dur, 0, 1)
        local ang2 = s.a0 + u * 7.0             -- 渦を巻いて中心へ
        local rr = s.r0 * (1 - u)
        local x = self.bx + math.cos(ang2) * rr
        local y = cy + math.sin(ang2) * rr * 0.7
        s.rot = s.rot + 720 * dt
        if done then
          s.e.transform.position = Vec3.new(x, -100, self.bz)
        else
          s.e.transform.position = Vec3.new(x, y, self.bz - 0.15)
          s.e.transform.rotation = Vec3.new(0, 0, s.rot % 360)
          scene:setMeshEffect(s.e, 2.8)         -- 紫の後戻り発光
          if math.random() < 0.4 then FX.trail(x, y, self.bz, 0.75, 0.5, 1.0) end
        end
      end
    end
    if done then
      self.reviveFx = nil
      -- 合体の瞬間: 白紫の閃光+二重衝撃波。この後1秒静止(swingHold)してから振り子再開
      FX.spark(self.bx, cy, self.bz, 50, 0.8, 0.6, 1.0)
      FX.spark(self.bx, cy, self.bz, 30, 1.0, 1.0, 1.0)
      FX.shockwave(self.bx, cy, self.bz, 22, 14, 0.65, 0.4, 1.0)
      FX.shockwave(self.bx, cy, self.bz, 12, 20, 0.9, 0.8, 1.0)
      fx:pulse(0.35)
      self.swingHold = 1.0
    end
  end

  -- 崩壊破片の弾道アニメ(重力+接地バウンド+粉塵の尾、1.8秒で灰の山に沈んで消える)
  if self.fragFx then
    local alive = false
    for _, f in ipairs(self.fragFx) do
      if f.e and f.e:isValid() then
        f.t = f.t + dt
        if f.t < 1.8 then
          alive = true
          f.vy = f.vy - 24 * dt
          f.x = f.x + f.vx * dt
          f.y = f.y + f.vy * dt
          if f.y < groundY + 0.08 then
            f.y = groundY + 0.08
            if math.abs(f.vy) > 2.0 then     -- 強い着地はガツンと火花
              FX.spark(f.x, f.y, self.bz, 6, 0.9, 0.6, 0.3)
            end
            f.vy = math.abs(f.vy) * 0.45     -- 跳ね返り(減衰)
            f.vx = f.vx * 0.65
          end
          f.rot = f.rot + f.spin * dt
          -- 飛行中は粉塵の尾を引く(速度があるうちだけ)
          if f.vx * f.vx + f.vy * f.vy > 4.0 and math.random() < 0.5 then
            FX.trail(f.x, f.y, self.bz, 0.62, 0.58, 0.5)
          end
          f.e.transform.position = Vec3.new(f.x, f.y, self.bz - 0.1)
          f.e.transform.rotation = Vec3.new(0, 0, f.rot % 360)
        else
          f.e.transform.position = Vec3.new(f.x, -100, self.bz)
        end
      end
    end
    if not alive then self.fragFx = nil end
  end

  local rad = math.rad(ang)
  local hx = self.bx + math.sin(rad) * R
  local hy = self.by - math.cos(rad) * R

  -- 的判定ボックス(自名+"X")。旧実装は「可動域全体を覆う静的な箱」で、ヘッドが
  -- いない高さの水平弾道まで吸っていた(2026-07-24ユーザー指摘×3)。
  -- 通常時: 【いまヘッドがある場所】へ毎フレーム追従する小箱だけにする。
  -- チリ状態: 山の的箱は床下へ沈める(的の最低保証±0.8があるため、床上に置くと
  --   地上弾道が必ず掠る)。復活させたい時は山を狙って撃ち下ろせば届く
  local xE = scene:findEntity(self.name .. "X")
  if xE and xE:isValid() then
    if self.lastStage == 4 then
      xE.transform.position = Vec3.new(self.bx, groundY - 0.55, self.bz)
      xE.transform.scale = Vec3.new(2.4 * self.transform.scale.y, 0.5, 1.0)
    else
      xE.transform.position = Vec3.new(hx, hy, self.bz)
      xE.transform.scale = Vec3.new(1.4 * self.transform.scale.y, 1.4 * self.transform.scale.y, 1.0)
    end
  end

  -- 劣化度(0=新品〜0.95=ぼろぼろ)をシェーダーへ: 錆の侵食+ヒビ+欠け落ち
  local deg = math.min(0.95, self.clock / (self.decayT * 2.5))
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 6.0 + deg
    if self.ffRemain > 0 then eff = 1.0
    elseif self.rwGlow > 0 then eff = 2.8 end
    if self.aimPv then
      self.aimPv.t = self.aimPv.t - dt
      if self.aimPv.t > 0 then
        eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
      else
        self.aimPv = nil
      end
    end
    scene:setMeshEffect(selfE, eff)
  end
  if self.ffRemain > 0 then FX.trail(hx, hy, self.bz, 0.3, 0.9, 1.0) end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(hx, hy, self.bz, 0.65, 0.4, 1.0)
  end

  -- 火花: 摩耗以降、振りの最下点を通過する瞬間にガリッと研削火花が散る
  if self.lastStage and self.lastStage >= 2 and self.lastStage < 4 then
    local s = math.sin(self.phase * math.pi * 2)
    if math.abs(s) < 0.10 then
      if not self.sparked then
        self.sparked = true
        audio:playSpatial("audio/se/hammer_hit.wav", hx, hy - 0.4, self.bz, 3, 20, 0.8)  -- 最下点通過のガリッ
        local n = (self.lastStage == 3) and 40 or 22
        FX.spark(hx, hy - 0.4, self.bz, n, 1.0, 0.75, 0.2)
        FX.spark(hx, hy - 0.3, self.bz, n, 1.0, 0.5, 0.1)
        FX.spark(hx, hy - 0.5, self.bz, math.floor(n / 2), 1.0, 0.9, 0.4)
        FX.shockwave(hx, hy - 0.4, self.bz, 8, 5, 1.0, 0.6, 0.2)
        fx:pulse(self.lastStage == 3 and 0.1 or 0.05)
      end
    else
      self.sparked = false
    end
  end

  -- 劣化した個体は錆粉を撒き、末期はヨレて震える(見た目のみ。判定は本来の角度)
  if self.lastStage and self.lastStage >= 2 and self.lastStage < 4 then
    self.dustT = (self.dustT or 0) + dt
    if self.dustT > (self.lastStage == 3 and 0.18 or 0.45) then
      self.dustT = 0
      FX.trail(hx + (math.random() - 0.5) * 0.6, hy - 0.3, self.bz, 0.55, 0.3, 0.12)
    end
    if self.lastStage == 3 then
      local wob = math.sin(self.phase * math.pi * 11) * 2.2   -- ガタつき
      local vis = scene:findEntity(self.name .. "_m3")
      if vis and vis:isValid() then
        vis.transform.rotation = Vec3.new(0, 0, ang + wob)
      end
      -- 常時火の粉シャワー(ヘッドから尾を引く)
      self.embT = (self.embT or 0) + dt
      if self.embT > 0.06 then
        self.embT = 0
        FX.spark(hx + (math.random() - 0.5) * 0.5, hy, self.bz, 3, 1.0, 0.55, 0.15)
      end
    end
  end

  if self.ffRemain > 0 then return end   -- 早送り中は経由位相で殺さない
  if self.lastStage and self.lastStage >= 4 then return end  -- チリ: 触れても安全(残骸に判定なし)
  -- 復活演出中と静止中も判定なし(組み上がる場所に立っていて即死しないように)
  if self.reviveFx or (self.swingHold or 0) > 0 then return end
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp = pl.transform.position
  if math.abs(pp.x - hx) < (self.hitHalf + 0.30) and math.abs(pp.y - hy) < (self.hitHalf + 0.42) then
    events:emit("player_died", {})
  end
  -- 腕(はり)にも当たり判定: 支点→ヘッド間を3点サンプリング(腕は細いので小半径)
  for i = 1, 3 do
    local r = R * i * 0.25
    local ax = self.bx + math.sin(rad) * r
    local ay = self.by - math.cos(rad) * r
    if math.abs(pp.x - ax) < (0.25 + 0.30) and math.abs(pp.y - ay) < (0.25 + 0.42) then
      events:emit("player_died", {})
      break
    end
  end
end
