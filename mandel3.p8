pico-8 cartridge // http://www.pico-8.com
version 29
__lua__

function _init()
  colors={1,2,5,4,3,13,9,8,14,6,15,12,11,10,7}

  orig_field_of_view=1/6
  orig_draw_distance=4
  orig_turn_amount=.005
  orig_speed = .05

  --debug stuff, disable for release
  force_draw_width=false
  debug=false
  --

  largest_width=0
  max_screenx_offset=0
  skipped_columns=0

  field_of_view=orig_field_of_view -- 45*
  draw_distance=orig_draw_distance
  turn_amount=orig_turn_amount
  speed = orig_speed
  height_zoom_ratio = 1.05
  screen_width = -sin(field_of_view/2) * 2

  player_height = 0.3
  grid_size = 1/(2^4)

  player = {
    coords=makevec2d(-0.5,0),
    bearing=makeangle(0)
  }

  prog_man={
    current_max_iterations=1
  }

  buffer_manager = build_buffer_manager()
end

function _update60()
  local offset = makevec2d(0,0)
  local facing = player.bearing:tovector()
  changed_position=false
  changed_height=false
  if btn(0) then
    changed_position=true
    player.bearing-=turn_amount
  end
  if btn(1) then
    changed_position=true
    player.bearing+=turn_amount
  end
  if btn(2) then
    changed_position=true
    offset+=facing
  end
  if btn(3) then
    changed_position=true
    offset-=facing
  end
  if btn(4) then
    changed_height=true
    player_height/= height_zoom_ratio
  end
  if btn(5) then
    changed_height=true
    player_height*= height_zoom_ratio
  end

  player.coords+= offset*speed*player_height

  tick_bearing_v()

  prog_man.current_max_iterations+=1/6
end

function tick_bearing_v()
  if abs(player_bearing_v) > .0005 then
    player_bearing_v-= tounit(player_bearing_v)*.0005
    player.bearing+=player_bearing_v
  end
end

progressive_coroutine=false
first_draw=true
function _draw()
  if changed_position or changed_height or first_draw then
    draw_background()
    progressive_coroutine=cocreate(raycast_walls_progressively)
  end
  assert(coresume(progressive_coroutine,prog_man))

  if debug then
    debug_info()
  end

  first_draw=false
end

function debug_info()
  --printh("DEBUG")
  --printh(player.bearing.val)
  --printh(tostr(player.coords.x)..","..tostr(player.coords.y))
  printh(stat(7))
  printh(stat(1))
end

function draw_background()
  cls()
  --rectfill(0,0,127,63,1) --sky
  --rectfill(0,64,127,127,0) --ground
  draw_stars()
end

stars={}
function draw_stars()
  stars={}
  local x,y,angle
  color(7)
  angle=player.bearing-field_of_view/2
  local init=flr(angle.val*100)
  local final=flr((angle.val+field_of_view)*100)
  local x
  for i=init,final do
    x=flr((i-init)/100/field_of_view*128)
    if not stars[x] then
      stars[x]={}
    end
    add(stars[x],flr(64-((i*19)%64)*orig_field_of_view/field_of_view))
  end
end

function raycast_walls_progressively(prog_man)
  local screenx=0
  local pixel_columns={}
  local buffer_manager=build_buffer_manager()

  for i=0,127,16 do
    add(pixel_columns,{
      calc_screenx=i,
      screenx=i,
      prog_man=prog_man,
      draw_width=16
    })
  end
  for i=8,127,16 do
    add(pixel_columns,{
      calc_screenx=i,
      screenx=i,
      prog_man=prog_man,
      draw_width=8
    })
  end
  for i=4,127,8 do
    add(pixel_columns,{
      calc_screenx=i,
      screenx=i,
      prog_man=prog_man,
      draw_width=4
    })
  end
  for i=2,127,4 do
    add(pixel_columns,{
      calc_screenx=i,
      screenx=i,
      prog_man=prog_man,
      draw_width=2
    })
  end
  for i=1,127,2 do
    add(pixel_columns,{
      calc_screenx=i,
      screenx=i,
      prog_man=prog_man,
      draw_width=2
    })
  end

  buffer_manager:reset_state(.9)

  for i=1,#pixel_columns do
    raycast_pixel_column(pixel_columns[i])

    buffer_manager.progress_ratio+=1/128
    if not buffer_manager:is_finishable(1/128) then
      yield()
      prog_man.current_max_iterations+=1/6

      buffer_manager:reset_state(.9) --temporary hack to sidestep the buffer manager bug where it isn't compensating for the buffer
    end
  end

  pixel_columns={}
  buffer_manager:reset_state(.9)

  while true do
    if not pixel_columns[screenx] then
      pixel_columns[screenx] = {
        calc_screenx=screenx,
        screenx=screenx,
        prog_man=prog_man,
        draw_width=1
      }
    end
    raycast_pixel_column(pixel_columns[screenx])

    screenx+=1
    if screenx > 127 then
      screenx=0
    end
    --screenx=flr(rnd(128))

    buffer_manager.progress_ratio+=1/128
    if not buffer_manager:is_finishable(1/128) then
      yield()
      prog_man.current_max_iterations+=1/6

      buffer_manager:reset_state(.9) --temporary hack to sidestep the buffer manager bug where it isn't compensating for the buffer
    end
  end
end

function raycast_pixel_column(pixel_column) -- TODO: pass in a copy of the player
  local pa,pv,currx,curry,found,intx,inty,xstep,ystep,distance
  local height,distance_to_pixel_col,screeny,max_y,lowest_y,current_draw_distance,blocker_ratio
  local calc_screenx,screenx,draw_width
  local prog_man=pixel_column.prog_man

  calc_screenx=pixel_column.calc_screenx
  if not pixel_column.pa then
    pixel_column.pa=screenx_to_angle(calc_screenx) -- TODO: make this take in a copy of the player
  end
  pa=pixel_column.pa

  if not pixel_column.pv then
    pixel_column.pv=pa:tovector()
  end
  pv=pixel_column.pv

  screenx=pixel_column.screenx
  draw_width=pixel_column.draw_width

  currx=round(player.coords.x/grid_size)*grid_size
  curry=round(player.coords.y/grid_size)*grid_size
  xstep=towinf(pv.x)*grid_size
  ystep=towinf(pv.y)*grid_size

  -- TODO: make this stuff work with the variable grid size
  -- take the largest coord difference from player coord (eg, if most of the difference is across x, then take x difference)
  -- for some number Z indicating how big the grid is, make the grid ceil(x_difference/Z)
  -- that way it won't switch grids in the middle of a larger grid
  -- for this to work, the result needs to be only powers of 2... or rather, each new grid size needs to be double the last
  -- haven't figured out whether the raw value should be rounded up to the next power of two or down to the last

  if abs(pv.x) > abs(pv.y) then
    intx= currx - xstep/2
    distance = (intx - player.coords.x) / pv.x
    inty= player.coords.y + distance * pv.y
  else
    inty= curry - ystep/2
    distance = (inty - player.coords.y) / pv.y
    intx= player.coords.x + distance * pv.x
  end

  found=false

  distance_to_pixel_col = 1/cos(pa.val-player.bearing.val)
  max_y = 127
  lowest_y = 128
  current_draw_distance=min(2,draw_distance*player_height)
  blocker_ratio=false
  did_draw=false
  local max_wall_height=prog_man.current_max_iterations/1000
  local front_distance,temp_max_y

  while not found and distance < current_draw_distance do
    if (currx + xstep/2 - intx) / pv.x < (curry + ystep/2 - inty) / pv.y then
      intx= currx + xstep/2
      distance = (intx - player.coords.x) / pv.x
      inty= player.coords.y + distance * pv.y
      currx+= xstep
    else
      inty= curry + ystep/2
      distance = (inty - player.coords.y) / pv.y
      intx= player.coords.x + distance * pv.x
      curry+= ystep
    end
    front_distance=distance

    iterations = mandelbrot(currx, curry, prog_man.current_max_iterations) --flr(10*(currx+curry))

    if iterations < flr(prog_man.current_max_iterations) then
      height = (prog_man.current_max_iterations-iterations)/1000
      relative_height = height - player_height

      if relative_height < 0 then
        -- hack to make the distance calculated to the far wall rather than close wall for if we can see the top so it doesn't look empty
        -- distance gets overwritten each iteration so this is (for now) fine to do
        -- there's probably a more efficient way to do this, but screw it
        if (currx + xstep/2 - intx) / pv.x < (curry + ystep/2 - inty) / pv.y then
          distance = (currx + xstep/2 - player.coords.x) / pv.x
        else
          distance = (curry + ystep/2 - player.coords.y) / pv.y
        end
      end

      screen_distance_from_center = relative_height * distance_to_pixel_col / distance

      pixels_from_center = 128 * (screen_distance_from_center/screen_width)
      screeny = flr(63.5 - pixels_from_center)

      if screeny <= max_y then
        if not did_draw then
          temp_max_y=min(max_y,ceil(63.5 - 128 * ((-player_height * distance_to_pixel_col / front_distance)/screen_width))) --y of bottom front of stretched cube
          if temp_max_y < max_y then
            rectfill(screenx, temp_max_y+1, screenx+draw_width-1, max_y, 0)
          end
          max_y=min(temp_max_y,max_y)
        end

        if relative_height > 0 then
          current_draw_distance=min(current_draw_distance,distance * (max_wall_height-player_height)/relative_height)
        end

        did_draw=true
        rectfill(screenx, max_y, screenx+draw_width-1, screeny, colors[1+(iterations%14)])
        lowest_y = min(screeny,lowest_y)
        max_y = screeny-1
        --printh(draw_width)
      end
    else
      did_draw=false
    end
  end

  if lowest_y > 0 then
    rectfill(screenx, lowest_y-1, screenx+draw_width-1, 0, 0)
    for starx=screenx,screenx+draw_width-1 do
      if stars[starx] then
        for i=1,#stars[starx] do
          if stars[starx][i] < lowest_y then
            pset(starx, stars[starx][i], 7)
          end
        end
      end
    end
  end
end

build_buffer_manager = (function()
  local buffer_percent=0.2 --TODO - this seems to have little to no effect for progressive, double check the logic

  local function reset_state(obj,total_time)
    obj.start_time=stat(1)
    obj.alotted_time=total_time-obj.start_time

    obj.start_time+=buffer_percent*obj.alotted_time
    obj.alotted_time-=buffer_percent*obj.alotted_time

    obj.progress_ratio=0
  end

  local function skip_ratio(obj)
    --behind_time=stat(1)-(obj.start_time+progress_ratio*obj.alotted_time-obj.buffer_time)
    --skip_ratio=behind_time/obj.alotted_time
    --v reduced from ^
    return (stat(1)-obj.start_time)/obj.alotted_time + buffer_percent - obj.progress_ratio
  end

  local function is_finishable(obj,additional_progress)
    local spent_time = stat(1) - obj.start_time
    -- local remaining_time = obj.alotted_time - spent_time
    -- local progress_rate = obj.progress_ratio / spent_time
    -- local additional_time_to_finish = additional_progress / progress_rate
    -- return remaining_time >= additional_time_to_finish
    -- v from this ^

    return spent_time <= 0 or obj.alotted_time/spent_time - 1 >= additional_progress / obj.progress_ratio
  end

  return function()
    local obj={
      reset_state=reset_state,
      skip_ratio=skip_ratio,
      is_finishable=is_finishable
    }
    obj:reset_state(1)
    return obj
  end
end)()

cached_grid={}
function mandelbrot(x, y, current_max_iterations)
  y=abs(y)
  local key=tostr(x,true)..tostr(y,true)
  if not cached_grid[key] then
    cached_grid[key]={
      x=0,
      y=0,
      i=0
    }
  end

  -- if true then
  --   return 16-mid(1,15,10*(abs(x)+abs(y)))
  --   --return 8
  -- end

  current_max_iterations=flr(current_max_iterations)

  local zx=cached_grid[key].x
  local zy=cached_grid[key].y
  local xswap

  local i=cached_grid[key].i
  while i < current_max_iterations and abs(zx) < 2 and abs(zy) < 2 do
    i+= 1

    xswap = zx*zx - zy*zy + x
    zy = (zy + zy)*zx + y
    zx = xswap
  end

  cached_grid[key].x = zx
  cached_grid[key].y = zy
  cached_grid[key].i = i

  return i
end

function screenx_to_angle(screenx)
  local offset_from_center_of_screen = (screenx - 127/2) * (screen_width/128)
  return makeangle(player.bearing.val+atan2(offset_from_center_of_screen, 1)+1/4)
end

--NB - not currently used
function angle_to_screenx(angle)
  local offset_from_center_of_screen = -sin(angle.val-player.bearing.val)
  return round(offset_from_center_of_screen/screen_width * 128 + 127/2)
end

makeangle = (function()
  local mt = {
    __add=function(a,b)
      if type(a) == "table" then
        a=a.val
      end
      if type(b) == "table" then
        b=b.val
      end
      local val=a+b

      if val < 0 then
        val = abs(flr(val))+val
      elseif val >= 1 then
        val = val%1
      end
      return makeangle(val)
    end,
    __sub=function(a,b)
      if type(b) == "number" then
        return a+makeangle(-b)
      else
        return a+makeangle(-b.val)
      end
    end
  }
  local function angle_tovector(a)
    return makevec2d(cos(a.val-.25),sin(a.val-.25))
  end
  return function(angle)
    local t={
      val=angle,
      tovector=angle_tovector
    }
    setmetatable(t,mt)
    return t
  end
end)()

makevec2d = (function()
  mt = {
    __add = function(a, b)
      return makevec2d(
        a.x + b.x,
        a.y + b.y
      )
    end,
    __sub = function(a,b)
      return a+makevec2d(-b.x,-b.y)
    end,
    __mul = function(a, b)
      if type(a) == "number" then
        return makevec2d(b.x * a, b.y * a)
      elseif type(b) == "number" then
        return makevec2d(a.x * b, a.y * b)
      else
        return a.x * b.x + a.y * b.y
      end
    end,
    __div = function(a,b)
      return a*(1/b)
    end,
    __eq = function(a, b)
      return a.x == b.x and a.y == b.y
    end
  }
  local function vec2d_tostring(t)
    return "(" .. t.x .. ", " .. t.y .. ")"
  end
  local function magnitude(t)
    return sqrt(t.x*t.x+t.y*t.y)
  end
  local function bearing(t)
    return makeangle(atan2(t.x,t.y))+.25
  end
  local function diamond_distance(t)
    return abs(t.x)+abs(t.y)
  end
  local function normalize(t)
    return t/t:tomagnitude()
  end
  local function project_onto(t,direction)
    local dir_mag=direction:tomagnitude()
    return ((direction*t)/(dir_mag*dir_mag))*direction
  end
  local function cross_with(t,vector)
    -- signed magnitude of 3d cross product
    return t.x*vector.y-t.y*vector.x
  end
  return function(x, y)
    local t = {
    x=x,
    y=y,
    tostring=vec2d_tostring,
    tobearing=bearing,
    tomagnitude=magnitude,
    diamond_distance=diamond_distance,
    project_onto=project_onto,
    cross_with=cross_with,
    normalize=normalize
    }
    setmetatable(t, mt)
    return t
  end
end)()

function round(n)
  return flr(n+0.5)
end

function towinf(n) -- rounds to the larger number regardless of sign (eg, -0.4 to -1)
 if n > 0 then
  return -flr(-n)
 else
  return flr(n)
 end
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
52222222255505555500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
52222222255505555500000000000000000000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000
52222222255555555500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000700000
44222222255555555555555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555522202222200000000000000000000000000000070000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555522202222220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555522222222220000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555522222222222222222222222222220000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555542222222222222222222222222222000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555542222222222222222222222222222000000000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555542222222222222222222222222222555555000000000000000000000000000000000000000000000000000000000000000
44222222255555555555555555555542222222222444222222222222222555555000000000000000000000000000700000000000000000000000000000000000
44d22222255555555555555555555542222222222444222222222222222555555555550000000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555542222222224444222222222222222555555555550000000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555542222222224444422222222222222555555555555500000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555542222222224444422222222222222555555555555500000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555542222222224444422222222222222555555555555550000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555542222222224444422222222222222555555555555550000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555542223222224444422222222222222555555555555550000000000000000000000000000000000000000007000000000000
44d22222255555555555555555555542223222224444432222222222222555555555555550000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555543223222224444432222222222222555555555555554000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555543223322224444433222222222222555555555555554000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555543223322224444433222222222222555555555555554000000000000000000000000000000000000000000000000000000
44d22222255555555555555555555543223322224444433222222222222555555555555554220000000000000000000000000000000000000000000000000000
44d22222255555555555555555555543223322224444433222222222222555555555555554220000000000000000000000000000000000000000000000000000
44d22222255555555555555555555543223322224444433222222222222555555555555554225550000000000000000000000000000000000000000000000000
44d22222255955555555555555555543223322224444433222222222222555555555555554225555000000000000000000000000000000000000000000000000
44d22222255955555555555555555543223322224444433222222222222555555555555554225555520000000000000000000000000000000000000000000000
44d22222255955555555555555555543223322224444433222222222222555555555555554244555522222222200000020000000000000000000000000000000
44d22222255995555555555555555543223322224444433d22222222222555555555555554244555552222222222222220000000000000000000000000000000
44d22222255995555555555555555543223322224444433d22222222222555555555555554344355552222222222222225500000000000000000000000000000
44d22222255995555555555555555543223322224444433d22222222222555555555555554344355552222222222222225550000000000000000000000000000
44d22222255995555555555555555543223322224444433d22222222222555555555555554344355552222222222222225555000000000000000000000000000
44d22222255995555555555555555543293322224444433d22222222222555555555555554344355552222222222222225555550000000000000000000000000
44d22222255995555555555555555543293322224444433d22222222222555555555555554344355552322222222222225555554000000000000000000000000
44d22222255995555555555555555543293322224444433d22222222222555555555555554344355552322222222222225555554000000000000000000044440
44d22222255995555555555555555543293322224444433d22222222222555555555555554344355552332222222222225555554000000000000000000044440
44d22222255995555555555555555543293322224444433d22222222222555555555555554344355552332222222222225555554400700000000000000044440
44d22222255995555555555555555543293322224444433d222222222225555555555555543443d5552332222222222225555554400000000000000000044440
44d22222255995555555555555555543293322224444433d222222222225555555555555543443d5552332222222222225555554400000000000000000044443
44d22222255995555555555555555543293322224444433d222222222225555555555555543443d555d332222222222225555554400000000000000000044443
44d22222255995555555555555555543293322284444433d222222222225555555555555543443d555d332222222222225555554400000000000000000044443
44d22222255995555555555555555543293322284444433d222222222225555555555555543443d555d332222222222225555554400000000000000000d44443
44d22222255995555555555555555543293322284444433d222222222225555555555555543443d555d3322222222222255555544d0000000000000000d44443
44d22222255995555555555555555543293322284444433d222222222225555555555555543443d555d3322222222222255555544d0000000000000000d44443
44d2ee22255995555555555555555543293322284444433d222222222225555555555555543443d555d3322222222222255555544d0000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d0000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d0000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d0000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d0000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d8000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d8000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d8000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d8000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d8000000000000000d44443
44d2ee22255995555555555555555543293382284444433d222222222225555555555555543443d555d3392222222222255555544d8000000000000000d44443
44d2ee22255995555555555555555543293382284444433d22222e222225555555555555543443d555d3392222222222255555544d8000000000000000d44443
44d2ee22255995555555555555555543293382284444433d22222e222225555555555555543443d555d339222222222e255555544d8000000000000000d44443
44d2ee22256996555555555555555543293386684444433d22222e222225555555555555543443d555d339222222222e255555544d8000000000000000d44443
44d2ee22256996555555555555555543293386684444433d22222e222225555555555555543443d555d339222222222e255555544d8000000000000600d44443
44d2ee22256996555555555555555543293386684444433d22222e222225555555555555543443d555d339222222222e255555544d8000000000000600d44443
44d2ee22256996555555555555555543293386684444433d22222e222225555555555555543443d555d339222222222e255555544d8000000000000600d44443
44d2ee22256996555555555555555543293386684444433d22222e222225555555555555543443d555d339222222222e255555544d8000000000000600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222e255555544d8000000000000600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222e255555544d800000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222e255555544d8f0000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222e255555544d8f0000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222e255555544d8f0000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222e255555544d8f0000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222e255555544d8f0000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222ec55555544d8f0000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222ec55555544d8f0000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222ec55555544d8f0000000000f600d44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d339222222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3392b2222222ec55555544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3390b0000000ec00000544d8f0000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3390b0000000ec000000000000000000000f60bd44443
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3390b0000000ec0000000000000000000000000000000
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3390b0000000ec0000000000000000000000000000000
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d555d3390b0000000ec0000000000000000000000000000000
44d2ee22256996555555555555555543293386684444433d22222e226225555555555555543443d0000000000000000ec0000000000000000000000000000000
44d2ee22256996555555555555555543293386684444433d222a2e226225555555555555543443d0000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e226225555555555555543443d0000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e226225555555555555543443d0000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e226225555555555555543443d0000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e226225555555555555543443d0000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e22622555555555555554000000000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e22622555555555555554000000000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e22622555555555555554000000000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e22622555555555555554000000000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e22622555555555555554000000000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e22622555555555555554000000000000000000000000000000000000000000000000000000
44d2ee22256996555555555555555543a93386684444433d222a2e22622555555555555554000000000000000000000000000000000000000000000000000000
44d2ee2225699655a555555555555543a93386684444433d222a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d2ee2225699655a555555555555543a93386684444433d000a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d2ee2225699655a555555555555543a93386684444433d000a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d2ee2225699655a555555555555543a93386684444433d000a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d2ee2225699655a555555555555543a93386684444433d000a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699655a555555555555543a93386684444433d000a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699655a555555555555543a93386684444433d000a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699655a555555555555543a93386684444433d000a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699655a555555555555543a93386684444433d000a0e00600000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699655a555555555555543a93386684444433d00000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699655a555555555555543a93300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699655a555555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699655a500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee2225699600a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee0000699600a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee0000699600a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee0000699600a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee0000699600a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee0000699600a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
44d7ee0000699600a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

