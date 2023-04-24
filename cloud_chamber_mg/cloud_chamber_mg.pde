/*
Resources:
Basic Motion Detection - https://www.youtube.com/watch?v=QLHMtE5XsMs
LazyGui - https://github.com/KrabCode/LazyGui

Good Lord help: https://groups.google.com/g/gstreamer-java/c/gKsEB8wjcxI

Notes:
Do NOT auto White Balance on Camera settings.
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

// Warning: Cannot find gstcairo.dll
import processing.video.*;
import processing.sound.*;

// Trying with a hardcoded resolution.
// Res. PC - 1920x1080, Laptop - 1366x768
final int RES_WIDTH = 1200;
final int RES_HEIGHT = 675;
// Column Width = 100
final int NUM_COLS = 12;
// Row Height = 75
final int NUM_ROWS = 9;

// Video and Image objects.
Capture video;
PImage prev;
PImage data;

// Array of Objects/Oscillators
oscRect[] rects;
SinOsc[] osc;
Env[] env;
Reverb reverb;
boolean isPlaying;

// Controller objects and variables.
LazyGui gui;
// Threshold for pixel change, as slider values.
int primaryThreshold, secondaryThreshold;
// Threshold wall boundaries, as slider values.
int leftBoundary, rightBoundary;
// Brightness threshold for reading pixels within a space.
int brightThreshold;

// Time related variables.
int oscFrames, reFrames, refresh;


void settings() {
  // This runs before setup.
  size(1200, 675, P2D);
}


void setup() {
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
  
  // Array of Objects.
  println("Box #: col, row, width, height, startP, numberPix, pix");
  int numberRects = NUM_COLS*NUM_ROWS;
  rects = new oscRect[numberRects];
  osc = new SinOsc[numberRects];
  env = new Env[numberRects];
  for (int i = 0; i < numberRects; i++) {
    //println("Box #: col, row, width, height, startP, numberPix, pix");
    // Oscillators must be initialized before the rects.
    osc[i] = new SinOsc(this);
    rects[i] = new oscRect(i);
    env[i] = new Env(this);
  }
  // Filter
  reverb = new Reverb(this);
  
  reFrames = 0;
  oscFrames = 0;
  
  // Print Debug
  println("Resolution: " + RES_WIDTH + " x " + RES_HEIGHT);
}


// Read video.
void captureEvent(Capture video) {
  video.read();
}


void draw() {
  //background(0);
  
  // Gui folder and elements for thresholds/boundaries/capture refresh/etc.
  primaryThreshold = gui.sliderInt("thresholds/primary", 80, 0, 200);
  secondaryThreshold = gui.sliderInt("thresholds/secondary", 80, 0, 200);
  boolean showBoundaries = gui.toggle("thresholds/hide\\/thresh");
  leftBoundary = gui.sliderInt("thresholds/left", 500, 0, RES_WIDTH/2);
  rightBoundary = gui.sliderInt("thresholds/right", RES_WIDTH/2+500, RES_WIDTH/2, RES_WIDTH);
  boolean refreshOff = gui.toggle("capture/auto\\/off");
  refresh = gui.sliderInt("capture/refresh", 120, 30, 600);
  brightThreshold = gui.sliderInt("visual/brightness", 100, 0, 255);
  // Gui button for capturing the current image.
  if (gui.button("capture/manual")) {
    // A fatal error occurs if you do not recreate the Image. I assume it is a memory allocation/corruption issue?
    // prev = createImage(RES_WIDTH, RES_HEIGHT, RGB);
    prev.copy(video, 0, 0, RES_WIDTH, RES_HEIGHT, 0, 0, RES_WIDTH, RES_HEIGHT);
    reFrames = 0;
  }
  // Toggle sound on/off.
  isPlaying = gui.toggle("music\\/off");
  
  // Load the pixels of each image/video/AND THE WINDOW.
  video.loadPixels();
  prev.loadPixels();
  data.loadPixels();
  // loadPixels();
  
  // Check if data array is the correct size.
  if (data.pixels.length != video.pixels.length) {
    data.resize(RES_WIDTH, RES_HEIGHT);
  }
  
  // Loop through all pixels - flipped, move invariants out of inner loop.
  // Can I just loop through based on length?
  for (int i = 0; i < video.pixels.length; i++) {
    // Determine previous color.
    color prevColor = prev.pixels[i];
    float r2 = red(prevColor);
    float g2 = green(prevColor);
    float b2 = blue(prevColor);
    // Determine current color of that pixel.
    color currentColor = video.pixels[i];
    float r1 = red(currentColor);
    float g1 = green(currentColor);
    float b1 = blue(currentColor);
    
    // Calculate the "difference" - distance in RGB space.
    float d = distSq(r1, g1, b1, r2, g2, b2);
    
    // Check against threshold of difference.
    // Logic for center vs. edge pixels, using % width, due to the extreme lighting variation.
    int modLoc = i % width;
    if (modLoc <= leftBoundary && modLoc >= rightBoundary && (d > (primaryThreshold*primaryThreshold))) {
      data.pixels[i] = currentColor;
    } else if (d > (secondaryThreshold*secondaryThreshold)) {
      data.pixels[i] = currentColor;
    } else {
      data.pixels[i] = color(0);
    }
  }
  data.updatePixels();
  
  image(video, 0, 0);
  
  // oscRect draw every frame.
  for (oscRect oR : rects) {
    if ((oscFrames % 4) == 3) {
      oR.update(data);
    }
    oR.draw();
    if (gui.toggle("visual/off\\/boxes")) {
      oR.drawBox();
    }
  }
  // In order for Capture to work P2D, you do this. Don't know why.
  //image(video, 0, 0);
  //image(data, 0, 0, RES_WIDTH, RES_HEIGHT);
  
  // Draw boundary lines for Debug.
  if (showBoundaries) {
    stroke(0,255,0);
    line(leftBoundary, 0, leftBoundary, RES_HEIGHT);
    line(rightBoundary, 0, rightBoundary, RES_HEIGHT);
  }
  
  // Debug view of captured "background" and rolling data image, toggled.
  boolean showImages = gui.toggle("hide\\/videos");
  if (showImages) {
    image(prev, 50, RES_HEIGHT-150, 192, 108);
    image(data, 242, RES_HEIGHT-150, 192, 108);
    //image(video, 434, RES_HEIGHT-150, 192, 108);
  }
  //} else {
  //  image(video, 0, 0, 0, 0);
  //}
  
  if (!refreshOff && reFrames == refresh) {
    // prev = createImage(RES_WIDTH, RES_HEIGHT, RGB);
    prev.copy(video, 0, 0, RES_WIDTH, RES_HEIGHT, 0, 0, RES_WIDTH, RES_HEIGHT);
    reFrames = 0;
  }
  
  // Increment frames for auto-refresh, osc.
  reFrames++;
  oscFrames++;
}


// Function for the distance squared, for comparison against threshold squared.
float distSq(float x1, float y1, float z1, float x2, float y2, float z2) {
  float d = (x2-x1)*(x2-x1) + (y2-y1)*(y2-y1) + (z2-z1)*(z2-z1);
  return d; 
}


class oscRect{
  // Class variables.
  int brightPix = 0;
  float prevSize, size, xCenter, yCenter;
  int index, rWidth, rHeight;
  int[] pix;
  float amp, freq;
  
  // Constructor.
  oscRect(int i) {
    //print("Box " + index + ": [");
    this.index = i;
    int col = (i % NUM_COLS) + 1;
    int row = ceil(i / NUM_COLS) + 1;
    this.rWidth = RES_WIDTH / NUM_COLS;
    this.rHeight = RES_HEIGHT / NUM_ROWS;
    int startP = ((row - 1)*(RES_WIDTH * this.rHeight)) + ((col - 1)*(this.rWidth));
    int numberPix = this.rWidth*this.rHeight;
    this.pix = new int[numberPix];
    //println(pix.length);
    int p = 0;
    for (int r = 0; r < rHeight; r++) {
      int horizontal = r * RES_WIDTH;
      for (int c = 0; c < this.rWidth; c++) {
        int pixLoc = startP + horizontal + c;
        //print(pixLoc, ", ");
        this.pix[p] = pixLoc;
        //print(this.pix[p] + ", ");
        p++;
      }
    }
    //println("]");
    this.xCenter = (col - 1)*this.rWidth + (this.rWidth/2);
    this.yCenter = (row - 1)*this.rHeight + (this.rHeight/2);
    //print("Box " + this.index + ": " + this.xCenter + ", " + this.yCenter);
    // Associated
    this.amp = (row * 0.0003);
    this.freq = findFreq(col);
    osc[this.index].amp(this.amp);
  }
  
  float findFreq(int col) {
    // Default to middle C, if issue.
    float f = 261.63;
    int add = col % 3;
    if (this.index < 4) {
      f = 65.406 + (add * 16.3);
    } else if (this.index < 7) {
      f = 130.81 + (add * 32.6);
    } else if (this.index < 10) {
      f = f + 65.2;
    } else {
      f = 523.25 + (add * 125.9);
    }
    return f;
  }
  
  // Functions.
  void update(PImage image) {
    // Reset size to zero, update based on new pixels.
    //println(image.pixels.length);
    this.prevSize = this.brightPix / 100;
    this.brightPix = 0;
    for (int p = 0; p < pix.length; p++) {
      int imgIndex = pix[p];
      //print(pix[p] + ", ");
      color imgPix = image.pixels[imgIndex];
      int isBright = int(brightness(imgPix));
      //println(isBright);
      if (isBright > brightThreshold) {
        // Increment size for each bright pixel.
        this.brightPix++;
      }
    }
    this.size = this.brightPix / 100;
    //print("BP: " + brightPix);
    //println();
  }
  
  void draw() {
    // Based on rolling size, draw something.
    // Text for size value - waaay too much text.
    //fill(255, 0, 0);
    //text(size, xCenter, yCenter);
    // Constructor: ellipse(x_center, y_center, width, height)
    if (this.size > 0 && this.size != this.prevSize) {
      noStroke();
      fill(255);
      ellipseMode(CENTER);
      ellipse(this.xCenter, this.yCenter, this.size, this.size);
      if (!isPlaying) {
        osc[this.index].play();
        osc[this.index].freq(this.freq);
        // AttackTime - SustainTime - SustainLevel - ReleaseTime
        env[this.index].play(osc[this.index], 0.001, 0.004, 0.3, 0.4);
      } else if (osc[this.index].isPlaying()) {
        osc[this.index].stop();
      }
    }
  }
  
  void drawBox() {
    stroke(0,0,255);
    noFill();
    rectMode(CENTER);
    rect(this.xCenter, this.yCenter, this.rWidth, this.rHeight);
  }
  
}
