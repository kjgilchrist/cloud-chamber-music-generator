/*
Resources:
Basic Motion Detection - https://www.youtube.com/watch?v=QLHMtE5XsMs
LazyGui - https://github.com/KrabCode/LazyGui

Good Lord help: https://groups.google.com/g/gstreamer-java/c/gKsEB8wjcxI

Notes:
Do NOT auto White Balance.
*/

// Libs
import com.krab.lazy.examples_intellij.*;
import com.krab.lazy.input.*;
import com.krab.lazy.*;
import com.krab.lazy.nodes.*;
import com.krab.lazy.stores.*;
import com.krab.lazy.themes.*;
import com.krab.lazy.utils.*;
import com.krab.lazy.windows.*;
import com.google.gson.*;
import com.google.gson.stream.*;
import com.google.gson.reflect.*;
import com.google.gson.internal.*;
import com.google.gson.internal.reflect.*;
import com.google.gson.internal.bind.*;
import com.google.gson.internal.bind.util.*;
import com.google.gson.internal.sql.*;
import com.google.gson.annotations.*;

import processing.video.*; // THIS DUMB ASS LIBRARY CAN'T FIND THE GSTREAMER NONSENSE

//Trying with a hardcoded Res. Laptop - 1366x768
final int RES_WIDTH = 1200;
final int RES_HEIGHT = 675;

// Video and Image objects.
Capture video;
PImage prev;
PImage data;
// Controller objects.
LazyGui gui;

// Threshold for pixel change, as slider values.
int primaryThreshold, secondaryThreshold;
// Threshold wall boundaries, as slider values.
int leftBoundary, rightBoundary;
// Time.
int frames, refresh;

void setup() {
  size(1200, 675, P2D);
  // fullScreen(P2D);
  // Check for available devices.
  String[] devices = Capture.list();
  if (devices.length == 0) {
    println("There are no cameras available for capture.");
    exit();
  } else {
    println("Available cameras:");
    for (int i = 0; i < devices.length; i++) {
      println(devices[i]);
    }
    // Default Capture device to first device - be aware that this will have issues if there are multiple cameras, e.g. built-in camera versus USB.
    // Constructor: Capture(parent, width, height, device, fps)
    video = new Capture(this, RES_WIDTH, RES_HEIGHT, devices[0]);
    video.start();
    // I need this otherwise loadPixels() throws null.
    prev = createImage(RES_WIDTH, RES_HEIGHT, RGB);
    data = createImage(RES_WIDTH, RES_HEIGHT, RGB);
  }  
  // Control items.
  gui = new LazyGui(this);
}

// Read video.
void captureEvent(Capture video) {
  video.read();
}

void draw() {
  // Increment frames for auto-refresh of prev.
  frames++;
  
  // Gui folder for changing capture device (if needed). WIP
  
  // Gui folder and elements for thresholds/boundaries/capture refresh.
  primaryThreshold = gui.sliderInt("thresholds/primary", 80, 0, 200);
  secondaryThreshold = gui.sliderInt("thresholds/secondary", 80, 0, 200);
  boolean showBoundaries = gui.toggle("thresholds/hide\\/show");
  leftBoundary = gui.sliderInt("thresholds/left", 500, 0, RES_WIDTH/2);
  rightBoundary = gui.sliderInt("thresholds/right", RES_WIDTH/2+500, RES_WIDTH/2, RES_WIDTH);
  boolean refreshOff = gui.toggle("capture/on\\/off");
  refresh = gui.sliderInt("capture/refresh", 120, 30, 600);
  // Gui button for capturing the current image.
  if (gui.button("capture/manual")) {
    // A fatal error occurs if you do not recreate the Image. I assume it is a memory allocation/corruption issue?
    // prev = createImage(RES_WIDTH, RES_HEIGHT, RGB);
    prev.copy(video, 0, 0, RES_WIDTH, RES_HEIGHT, 0, 0, RES_WIDTH, RES_HEIGHT);
    frames = 0;
  }
  
  // Load the pixels of each image/video/AND THE WINDOW.
  video.loadPixels();
  prev.loadPixels();
  data.loadPixels();
  loadPixels();
  
  // Check if data array is the correct size.
  if (data.pixels.length != video.pixels.length) {
    data.resize(RES_WIDTH, RES_HEIGHT);
  }
  
  // Loop through all pixels
  for (int x = 0; x < RES_WIDTH; x++) {
    for (int y = 0; y < RES_HEIGHT; y++) {
      // Find pixel location in 1D array.
      int loc = x + (y * RES_WIDTH);
      // Determine previous color.
      color prevColor = prev.pixels[loc];
      float r2 = red(prevColor);
      float g2 = green(prevColor);
      float b2 = blue(prevColor);
      // Determine current color of that pixel.
      color currentColor = video.pixels[loc];
      float r1 = red(currentColor);
      float g1 = green(currentColor);
      float b1 = blue(currentColor);
      
      // Calculate the "difference" - distance in RGB space.
      float d = distSq(r1, g1, b1, r2, g2, b2);
      
      // Check against threshold of difference.
      // Logic for center vs. edge pixels, using % width, due to the extreme lighting variation.
      int modLoc = loc % width;
      if (modLoc >= leftBoundary && modLoc <= rightBoundary) {
        if (d > (secondaryThreshold*secondaryThreshold)) {
          data.pixels[loc] = currentColor; //color(255);
        } else {
          data.pixels[loc] = color(0);
        }
      } else {
        if (d > (primaryThreshold*primaryThreshold)) {
          data.pixels[loc] = currentColor; //color(255);
        } else {
          data.pixels[loc] = color(0);
        }
      }
    }
  }
  data.updatePixels();
  
  // In order for Capture to work P2D, you do this. Don't know why.
  //image(video, 0, 0);
  image(data, 0, 0, RES_WIDTH, RES_HEIGHT);
  
  // Draw boundary lines for Debug.
  if (showBoundaries) {
    stroke(0,255,0);
    line(leftBoundary, 0, leftBoundary, RES_HEIGHT);
    line(rightBoundary, 0, rightBoundary, RES_HEIGHT);
  }
  
  // Debug view of captured "background" and rolling data image.
  image(prev, 50, RES_HEIGHT-150, 192, 108);
  //image(data, 242, RES_HEIGHT-150, 192, 108);
  image(video, 242, RES_HEIGHT-150, 192, 108);
  
  if (!refreshOff && frames == refresh) {
    // prev = createImage(RES_WIDTH, RES_HEIGHT, RGB);
    prev.copy(video, 0, 0, RES_WIDTH, RES_HEIGHT, 0, 0, RES_WIDTH, RES_HEIGHT);
    frames = 0;
  }
}

// Function for the distance squared, for comparison against threshold squared.
float distSq(float x1, float y1, float z1, float x2, float y2, float z2) {
  float d = (x2-x1)*(x2-x1) + (y2-y1)*(y2-y1) + (z2-z1)*(z2-z1);
  return d; 
}

class oscRect {
  // Class variables.
  int index, rWidth, rHeight;
  int[] pixel;
  
  // Constructor.
  oscRect (int i, int cols, int rows) {
    index = i;
    rWidth = RES_WIDTH / cols;
    rHeight = RES_HEIGHT / rows;
    for (int p = 0; p < (rWidth*rHeight); p++) {
      
    }
  }
  
  // Functions.
  void update() {
    
  }
}
