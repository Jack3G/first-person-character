# First Person Character Controller

This character controller is inspired by the Source engine and it's heritage
(GoldSrc, Quake, etc.), and has similar features like:
- Crouch jumping
- Air strafing
- Surfing

Currently updated to Godot 4.1.


# Problems I'm Having

This version feels a bit strange, surfing doesn't work properly. If you want to
see what the original version was like, go back to commit 6af3ceb (using godot
3). I'll see if I can improve this one though.

---
> Over a month later

The issue seems to be that `CharacterBody3D.move_and_slide()` doesn't change
the velocity like it says it does (or at least not the vertical). It does it
right in Godot 3.. Ok here's an example:

```
      Box
       v
     +---+                .-'|
     |   |            .-'    |
     +---+        .-'  Ramp  |
              .-'____________|
```

Imagine that there is **no gravity** and the box is a Kinematic/CharacterBody3D.
It starts with a bit of x velocity towards the ramp. This is how it would look
in Godot 3:

```
                              .-'
                          .-'
             Path->   .-'
     +---+        .-'     .-'|
     |   |------'     .-'    |
     +---+        .-'        |
              .-'____________|
```

You can see how the box's velocity is modified after touching the ramp. It has
turned some of the horizontal velocity into vertical.

This is how it looks in Godot 4:

```

                          .---------
                      .-'
     +---+        .-'     .-'|
     |   |------'     .-'    |
     +---+        .-'        |
              .-'____________|
```

The velocity stays the same throughout the entire motion, even while it's moving
up the ramp.

Both surfing and [Quake slopes](https://www.youtube.com/watch?v=vGYolaCaa78)
rely on the slope changing the velocity of the box on contact

Surfing needs to redirect the horizontal movement into vertical movement to
counteract gravity, and you only get a high jump from walking up slopes if
walking up a slope gives you upwards velocity.

One of the possible solutions I found was to put `self.velocity =
self.get_real_velocity()` at the top of the player's `_physics_process`. This
causes lots of issues with the jumping though, sometimes you'll get a tiny jump,
and sometimes you'll go way too high. I might be able to work around it.

The other solution that could work is using `move_and_collide` instead, and then
manually slide, snap, update velocity, etc. But that seems like a lot of effort :/

[move_and_slide source](https://github.com/godotengine/godot/blob/0ca8542329888e8dccba89d59d3b728090c29991/scene/3d/physics_body_3d.cpp#L1164)
for future reference. `_move_and_slide_grounded` is longer than the entire
player script at the moment though...
