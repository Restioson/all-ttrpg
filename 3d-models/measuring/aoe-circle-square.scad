$fn = $preview ? 0 : 128; 

/* [Basic options] */

// Scale: How many real-world milimetres represent 5 feet in world. Common scales are 5ft : 25mm, 5ft : 28mm, and 5ft : 25.4mm (= 1inch)
scale_5ft_in_mm = 25; 

// Whether to generate the following key, "(radius) [side]", which indicates that circle radii are in round () brackets and square side lengths are in [] square brackets
has_key = false;

// Radii for circles to generate. 0s will be ignored and not generated.
circle_radii_in_ft = [10, 15, 18, 0, 0, 0, 0, 0, 0, 0];

// Side lengths for squares to generate. Note that a 10ft-radius circle = 20ft cube, and so on. 0s will be ignored and not generated.
square_side_lengths_in_ft = [10, 20, 30, 36, 0, 0, 0, 0, 0, 0];

// The color of the text
text_color = undef;

/* [Rounding] */

// Radius for outer corner rounding (applies to the four outer corners, if a square is outside measuring shape). Cannot exceed wall_thickness/2 - 0.1. Set to 0 for no rounding.
outer_corner_radius = 1.9;

// Radius for inner corner rounding (applies to all other corners). Cannot exceed wall_thickness/2 - 0.1. Set to 0 for no rounding.
inner_corner_radius = 0;


/* [Walls and thickness] */

// Thickness of the measuring shapes - note that it is always the OUTER DIAMETER that indicates the measurement for a shape!
wall_thickness = 4;

// Height of the measuring shapes and the diagonal ribs
wall_height = 4;

/* [Text] */

// The font of the text. NOTE: if changing this, also change text_plaque_width and key_plaque_width
font = "Liberation Sans:style=Bold";


// The size of the text. NOTE: if changing this, also change text_plaque_width and key_plaque_width
font_size = 6;

// The width of a text plaque with one measurement
text_plaque_width = 20;

// The width of the plaque for the key
key_plaque_width = 54;

// How much to raise the text relative to the 
text_Z_height = 1;

// Aliases follow
    
in_radius = min(inner_corner_radius, wall_thickness / 2 - 0.1);
out_radius = min(outer_corner_radius, wall_thickness /2 - 0.1);
height = wall_height;
text_size = font_size;
text_height = text_Z_height;
thickness = wall_thickness;

function filter_zeroes(list) = [for (i = list) if (i != 0) i];
function ft_to_mm(ft) = ft / 5 * scale_5ft_in_mm;
function contains(list, item) = len(search(item, list)) > 0 ? true : false;

module rounded() {
    offset(r=-in_radius) offset(delta=in_radius)
        offset(r=out_radius) offset(delta=-out_radius)
            children();
}

module ribs(diagonal) {
    for (i = [-45, 45]) {
        rotate([0, 0, i])
            translate([0, 0])
                square([(diagonal) * 2, thickness], center=true);
    }
}

module text_plate(plate_text, text_width, plate_height) {    
    corner_delta = -1;
    corner_rad = 4;

    
    translate([0, -plate_height / 2 - corner_rad - corner_delta, 0]) {
        linear_extrude(height)
        offset(delta=corner_delta) 
            offset(r=corner_rad)
                square([text_width, plate_height], center=true);

        translate([0, 0, height]) {
            color(text_color)
                linear_extrude(text_height)
                    text(plate_text, size=text_size, halign="center", valign="center", font=font);
                    
        }
    }
}

module label(radius_ft) {
    radius = ft_to_mm(radius_ft);

    has_circle = contains(circle_radii_in_ft, radius_ft);
    has_square = contains(square_side_lengths_in_ft, radius_ft * 2);

    label_len = has_circle && has_square ? (text_plaque_width * 2) + 4 : text_plaque_width;
    circle_txt = str("(", radius_ft, "ft)");
    square_txt = str("[", radius_ft * 2, "ft]");
    
    full_txt = has_circle && has_square ? str(circle_txt, " ", square_txt)
                                        : (has_circle ? circle_txt : square_txt);

    translate([0, radius, 0])
        text_plate(full_txt, label_len, text_size);
}


module ring(radius_ft) {
    radius = ft_to_mm(radius_ft);
    
    difference() {
        circle(radius);

        translate([0, 0, -0.05])
            circle(r=radius - thickness);
    }

    intersection() {
        circle(radius);
        ribs(radius);
    }
}

module measuring_square(side_length_ft) {
    side_len = ft_to_mm(side_length_ft);

    difference() {
        square(side_len, center=true);
        square(side_len - (thickness * 2), center=true);
    }

    intersection() {
        translate([0, 0, height / 2])
            square([side_len, side_len], center=true);

        ribs(sqrt(2) * side_len / 2 + thickness);
    }
}


/* Measuring shapes */
linear_extrude(height) {
    in_radius = min(inner_corner_radius, wall_thickness / 2 - 0.1);
    out_radius = min(outer_corner_radius, wall_thickness /2 - 0.1);
    
    rounded() {
        for (i = filter_zeroes(circle_radii_in_ft)) {
            ring(i);
        }

        for (i = filter_zeroes(square_side_lengths_in_ft)) {
            measuring_square(i);
        }
    }
}

/* Labels */
for (i = filter_zeroes(circle_radii_in_ft)) {
    label(i);
}

for (i = filter_zeroes(square_side_lengths_in_ft)) {
    label(i / 2);
}

if (has_key) {
    translate([0, -19 + text_size,  0])
    text_plate("(radius) [side]", key_plaque_width, text_size);
}

