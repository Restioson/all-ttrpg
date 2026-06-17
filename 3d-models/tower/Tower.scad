// Credit for the spiral staircase underpart chamfer to u/ardvarkmadman on Reddit: https://www.reddit.com/r/openscad/comments/hi33op/my_supportless_61mm_spiral_staircase_designed/
// Credit for the pyramid and triangular prism to OpenSCAD wiki: // Taken from OpenSCAD wiki https://en.wikibooks.org/wiki/OpenSCAD_User_Manual/Primitive_Solids#polyhedron

$fn = $preview ? 32 : 128;

brick_scale = 9;
brick_width =  1.06 * brick_scale;
brick_height = 0.73 * brick_scale;
brick_length = 1.7 * brick_scale;

mm_per_ft = 5;

tower_radius_mm = 15 * mm_per_ft;
tower_height_mm = 175;


bricks_per_level = 36;
brick_z_gap = 1.38;
brick_level_jitter = 45;

stacker_height = 4;
stacker_r1 = tower_radius_mm + (brick_width / 2) - 2;
stacker_r2 = stacker_r1 - 2;
stacker_gap_mm = 30;
stacker_thickness_at_r2 = 2;

pi = 3.14159;

module tower_outside() {
    difference() {
        cylinder(tower_height_mm, r=tower_radius_mm + (brick_width / 2) - 0.4);
            
        translate([0, 0, -1])
            cylinder(tower_height_mm + 2, r=tower_radius_mm - (brick_width / 2) + 1.4);
    }
    
    // Stacker
    difference() {
        union() {
            cylinder(tower_height_mm, r=tower_radius_mm + (brick_width / 2) - 2);
            
            translate([0, 0, tower_height_mm]) {
                cylinder(stacker_height, r1=stacker_r1, r2=stacker_r2);
            }
        }
        
        cylinder(tower_height_mm + stacker_height + 0.1, r=stacker_r2 - stacker_thickness_at_r2);

        translate([0, 0, -1])
            cylinder(tower_height_mm + 6, r=tower_radius_mm - (brick_width * 0.6) + 2);

        translate([0, 0, tower_height_mm]) {
            cube([tower_radius_mm * 2 + 10, stacker_gap_mm + 0.3, 20], center=true);
            cube([stacker_gap_mm + 0.3,tower_radius_mm * 2 + 10, 20], center=true);
        }
    }


    for (level = [1:(tower_height_mm / (brick_height + brick_z_gap))]) {
        rotate([0, 0, brick_level_jitter * (level - 1)])
        translate([0, 0, (level - 1) * (brick_height + brick_z_gap)]) {
            r = tower_radius_mm - (brick_width / 2) + 0.5;

            difference() {
                union() {
                    translate([0, 0, 1])
                    cylinder(brick_height - 1, r=r + brick_width);

                    translate([0, 0, 0])
                    cylinder(1, r2=r + brick_width, r1=r + brick_width - 1);
                }
                
                translate([0, 0, -0.5])
                    cylinder(brick_height + 1, r=r);
                
                translate([0, 0, -0.5])
                    cylinder(2, r2=r, r1=r + 1);

                for (i = [0:bricks_per_level]) {
                    gap = brick_z_gap + 0.1;
                    
                    rotate([0, 0, 360 * i / bricks_per_level])
                    translate([r - 0.5, 0, -0.5])
                        cube([brick_width + 1, gap, brick_height + 1]);
                }
            }
        }
    }
}

// Taken from OpenSCAD wiki https://en.wikibooks.org/wiki/OpenSCAD_User_Manual/Primitive_Solids#polyhedron
module prism(l, w, h) {
    polyhedron(// pt      0        1        2        3        4        5
               points=[[0,0,0], [0,w,h], [l,w,h], [l,0,0], [0,w,0], [l,w,0]],
               // top sloping face (A)
               faces=[[0,1,2,3],
               // vertical rectangular face (B)
               [2,1,4,5],
               // bottom face (C)
               [0,3,5,4],
               // rear triangular face (D)
               [0,4,1],
               // front triangular face (E)
               [3,2,5]]
               );}

// Taken from https://www.reddit.com/r/openscad/comments/hi33op/my_supportless_61mm_spiral_staircase_designed/

module qtrcircle(sz){
intersection()
    {
        circle(sz);
        square(sz);
    }    
}


module stairs() {
    step_height = 10;
    step_up = 5;
    steps = (tower_height_mm / step_up) + 1;
    step_forward = 30;
    step_width = 40;
    full_turn = 360;
    
    intersection() {
        union() {            
            translate([0, 0, 0]) {
                for (step = [0:3:steps]) {
                    h = step > 27 ? 3 : 0;
                    rotate([0, 0, full_turn * (step - 1) / steps])
                    translate([0, tower_radius_mm - step_width, (step - 1) * step_up - 7 - h]) {
                        cube([step_forward, step_width, step_height + h]);
                    }
                }

                for (step = [3:3:steps - 1]) {
                    h = step > 27 ? 3 : 0;
                    x = 4;
                    z = ((step - 1) * step_up) + ((x) * (step_up / 2));
                    rot = (full_turn * (step - 1) / steps) + (full_turn * x * 0.56/ steps);
                    
                    
                    rotate([0, 0, rot])
                    translate([0, tower_radius_mm - step_width, z + -step_height / 2 - 6.5 - h]) {
                        cube([step_forward, step_width, step_height + 2.5 + h]);
                    }
                }
            
                // Chamfer under stairs
                stairwid=tower_radius_mm * 2;

                difference() {
                    translate([0, 0, 0])
                    intersection() {
                        union() {
                            rotate([0, 0, 180])
                            mirror([0, 1, 0])
                            linear_extrude(height=tower_height_mm,twist=360,slices=36) qtrcircle(stairwid/2);
                        }
                        
                        translate([0, 0, -1])
                            cylinder(tower_height_mm + 1, r=tower_radius_mm - 0.5);
                    }
                    
                    translate([0, 0, -1])
                        cylinder(tower_height_mm + 2, r=tower_radius_mm - step_width);
                    
                    translate([0, 0, -13])
                        scale([1, 1, 1])
                        rotate([0, 0, 180])
                        mirror([0, 1, 0])
                        // Taken from https://www.reddit.com/r/openscad/comments/hi33op/my_supportless_61mm_spiral_staircase_designed/
                        linear_extrude(height=tower_height_mm,twist=360,slices=360) qtrcircle(stairwid/2);
                    
                    translate([-tower_radius_mm - 10, -20, 100])
                        cube([tower_radius_mm + 10, tower_radius_mm + 40, tower_height_mm + 2]);
                }
            }
            
            // Top landing
            translate([-31, tower_radius_mm - step_width, steps * step_up - 5]) {
                difference() {
                    mirror([1, 0, 0])
                        mirror([0, 0, 1])
                        rotate([0, 0, 90])
                        prism(step_width, step_forward * 1.5, step_height + 5);
                        
                    translate([0, 0, -5])
                        cube([10, step_width, 10]);

                }
            }
            
            
    
            // Bottom ministep
            x = 4;
            rot = (full_turn * -1 / steps) + (full_turn * x * 0.56/ steps);

            rotate([0, 0, rot])
            translate([0, tower_radius_mm - step_width, 0]) {
                cube([step_forward, step_width, 5]);
            }

        }

        cylinder(tower_height_mm, r=tower_radius_mm - 0.5);
    }
}


module torches(type) {
    n_torches = 7;
    rotation = 40;
    first_rotation = 185;
    first_torch_height = 30;
    
    for (i = [1:n_torches]) {
        rotate([0, 0, rotation * (i - 1) + first_rotation])
        translate([0, -tower_radius_mm + 3, 20 * (i - 1) + first_torch_height]) {
            if (type == "torch") {
                rotate([-30, 0, 0]) {
                    cube([2, 2, 17]);
                }

                translate([0, 0, 8])
                cube([2, 6.5, 2]);
            } else if (type == "holes") {
                translate([1, 4, -60]) {
                    translate([1, 1, 0])
                    cylinder(50, r=3);
                }
            }
        }
    }
}

module windows() {
    n_windows = 5;
    rotation = 60;
    climb = 29.5;
    first_rotation = 217;
    first_height = 60;

    for (i = [1:n_windows]) {
        rotate([0, 0, rotation * (i - 1) + first_rotation])
            translate([0, -tower_radius_mm + 17, climb * (i - 1) + first_height]) {
            
            k = 11;
            translate([0, -1, -12.5])
            scale([1, 1, 0.6])
            rotate([90, 45, 0])
                pyramid(k, k * 2.5);

            difference() {
                isos(25, 30, 20);

                    
                translate([-10, -25, 0.01])
                    rotate([0, 90, 180])
                        isos(25, 20, 13);


                translate([-10, -25, -25 - 0.05])
                    rotate([0, 90, -180])
                        isos(25, 20, 10);
                    
                    
                translate([10, 0.1, -30 + 0.05])
                    rotate([0, 90, 0])
                        isos(25, 20, 10);
                    
                translate([10, 0.1, -30 - 0.05])
                    rotate([0, 90, 0])
                        isos(25, 20, 10);
            }

        }
    }
}


module tower_full() {
    difference() {
        union() {
            // Tower body
            difference() {
                tower_outside();

                // Cutaway
                translate([0, 0, -1])
                    cube([tower_radius_mm + 10, tower_radius_mm + 10, tower_height_mm + 10]);
                
                windows();
            }
            
            stairs();
        }
        
        // Stacker bottom
        difference() {
            translate([0, 0, -0.01])
                cylinder(stacker_height + 0.2, r1=stacker_r1 + 0.4, r2=stacker_r2 + 0.4);

            cylinder(stacker_height + 0.5, r=stacker_r2 - stacker_thickness_at_r2 - 0.3);
            
            translate([-5, -5, -1])
                cube([tower_radius_mm + 10, tower_radius_mm + 10, tower_height_mm + 10]);
        
                    
            // Stacker gap
            d = -tower_radius_mm + 0.5;

            translate([0, d, stacker_height / 2 + 1])
                cube([stacker_gap_mm, brick_width - 1, stacker_height + 2], center=true);

            translate([d, 0, stacker_height / 2 + 1])
                cube([brick_width - 1, stacker_gap_mm, stacker_height + 2], center=true);

            translate([-d, -stacker_gap_mm/4, stacker_height / 2 + 1])
                cube([brick_width - 1, stacker_gap_mm/2, stacker_height + 2], center=true);

            translate([-stacker_gap_mm/4, -d, stacker_height / 2 + 1])
                cube([stacker_gap_mm / 2, brick_width - 1, stacker_height + 2], center=true);

        }
    }
}



module isos(l, h, w) {
    rotate([0, 90, 90]) {
        translate([0, w/2, 0])
        prism(h, -w/2, -l);
        mirror([0, 1, 0])
        translate([0, w/2 - 0.0001, 0])
        prism(h, -w/2, -l);
    }
}

// Taken from OpenSCAD wiki https://en.wikibooks.org/wiki/OpenSCAD_User_Manual/Primitive_Solids#polyhedron
module pyramid(b, h) {
    polyhedron(
  points=[ [b,b,0],[b,-b,0],[-b,-b,0],[-b,b,0], // the four points at base
           [0,0,h]  ],                                 // the apex point 
  faces=[ [0,1,4],[1,2,4],[2,3,4],[3,0,4],              // each triangle side
              [1,0,3],[2,1,3] ]                         // two triangles for square base
 );
}

// We just render as the preview is laggy to pan around, while rendering is quick!
render()
tower_full();
