package engine;

import java.io.*;
import java.nio.*;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import javax.imageio.*;
import java.awt.image.*;

import org.lwjgl.Sys;
import org.lwjgl.BufferUtils;
import org.lwjgl.opengl.*;
import org.lwjgl.util.glu.GLU;

public final class GraphicEngine {
	// Display
	private static DisplayMode displayMode;

	// Map of texture filenames to corresponding Graphic objects
	private static HashMap<String, Graphic> textureMap;
	
	// Map of graphic functions to corresponding Graphic objects
	private static HashMap<GraphicFunction, Graphic> functionMap;
	
	private static HashMap<Graphic, int[]> displayListMap;

	// Render Set
	private static HashSet<Entity> renderSet;
	private static HashSet<Entity> seenSet;
	
	public static int shader;
	private static int vertShader;
	private static int fragShader;

	/**
	 * Initialises the Graphics Engine.
	 */
	@SuppressWarnings("unchecked")
	public static void initialise(String title) throws Exception {
		// Initialise Display
		DisplayMode d[] = Display.getAvailableDisplayModes();
		for (int i = 0; i < d.length; i++) {
			if (d[i].getWidth() == 800
					&& d[i].getHeight() == 600
					&& d[i].getBitsPerPixel() == 32) {
				displayMode = d[i];
				break;
			}
		}

		Display.setDisplayMode(displayMode);
		Display.setTitle(title);
		Display.setVSyncEnabled(true);

		PixelFormat pf = new PixelFormat(8, 16, 0, 4);//new PixelFormat().withSamples(4);
		Display.create(pf);
		//Display.create();

		GL11.glEnable(ARBMultisample.GL_MULTISAMPLE_ARB);

		// Initialise OpenGL
		GL11.glShadeModel(GL11.GL_FLAT);

		GL11.glEnable(GL11.GL_DEPTH_TEST);
		GL11.glDepthFunc(GL11.GL_LESS);

		GL11.glEnable(GL11.GL_BLEND);
		GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA);

		GL11.glHint(GL11.GL_PERSPECTIVE_CORRECTION_HINT, GL11.GL_FASTEST);

		GL11.glEnable(GL11.GL_CULL_FACE);

		// Projection Matrix
		GL11.glMatrixMode(GL11.GL_PROJECTION);
		GLU.gluPerspective(
				70.0f,
				(float) displayMode.getWidth() / (float) displayMode.getHeight(),
				0.1f,
				200.0f);

		// Model Matrix
		GL11.glMatrixMode(GL11.GL_MODELVIEW); // Select The Modelview Matrix
		GL11.glLoadIdentity();
		
		// Misc
		GL11.glLineWidth(1);
		GL11.glColor3ub((byte)255, (byte)255, (byte)255);
		
		// Shaders
		shader = ARBShaderObjects.glCreateProgramObjectARB();
		
		vertShader = ARBShaderObjects.glCreateShaderObjectARB(ARBVertexShader.GL_VERTEX_SHADER_ARB);
		fragShader = ARBShaderObjects.glCreateShaderObjectARB(ARBFragmentShader.GL_FRAGMENT_SHADER_ARB);
		
		String code = "", line;
		BufferedReader reader = new BufferedReader(new FileReader("res/shaders/vertex.shader"));
		while ((line = reader.readLine()) != null){
			code += line + "\n";
		}
		
		ARBShaderObjects.glShaderSourceARB(vertShader, code);
		ARBShaderObjects.glCompileShaderARB(vertShader);
		
		code = "";
		reader = new BufferedReader(new FileReader("res/shaders/fragment.shader"));
		while ((line = reader.readLine()) != null){
			code += line + "\n";
		}
		
		ARBShaderObjects.glShaderSourceARB(fragShader, code);
		ARBShaderObjects.glCompileShaderARB(fragShader);
		
        ARBShaderObjects.glAttachObjectARB(shader, vertShader);
        ARBShaderObjects.glAttachObjectARB(shader, fragShader);
        ARBShaderObjects.glLinkProgramARB(shader);
        ARBShaderObjects.glValidateProgramARB(shader);
        
        IntBuffer iVal = BufferUtils.createIntBuffer(1);
        ARBShaderObjects.glGetObjectParameterARB(shader, ARBShaderObjects.GL_OBJECT_INFO_LOG_LENGTH_ARB, iVal);

        int length = iVal.get();
        if (length > 1) {
            // We have some info we need to output.
            ByteBuffer infoLog = BufferUtils.createByteBuffer(length);
            iVal.flip();
            ARBShaderObjects.glGetInfoLogARB(shader, iVal, infoLog);
            byte[] infoBytes = new byte[length];
            infoLog.get(infoBytes);
            String out = new String(infoBytes);
            System.out.println("Info log:\n"+out);
        }

		// Initialise texture map
		textureMap = new HashMap<String, Graphic>();
		functionMap = new HashMap<GraphicFunction, Graphic>();
		renderSet = new HashSet<Entity>();
		seenSet = new HashSet<Entity>();
		displayListMap = new HashMap<Graphic, int[]>();;
	}
	
	/**
	 * Sets our window's title.
	 * 
	 * @param title
	 */
	public static void setTitle(String title) {
		Display.setTitle(title);
	}

	/**
	 * Preloads a graphic.
	 * @param
	 * 			filename	Filename of graphic to be preloaded
	 * @return
	 * 			Graphic object
	 */
	public static Graphic getGraphic(String filename, GraphicFunction func) {
		Graphic g = textureMap.get(filename);

		if (g == null) {
			System.out.println("Preloading Graphic: " + filename);

			try {
				BufferedImage img = ImageIO.read(new File("res/" + filename));

				// Get ARGB pixel int array from BufferedImage
				byte[] pixels = ((DataBufferByte)img.getRaster().getDataBuffer()).getData();

				// Convert to flipped RGBA pixel array
				pixels = convertPixels(pixels, img.getWidth(), img.getHeight());

				// Create buffer for image
				ByteBuffer imgBuffer = BufferUtils.createByteBuffer(pixels.length);
				imgBuffer.put(pixels);
				imgBuffer.flip();

				// Create buffer for texture id
				IntBuffer idBuffer = BufferUtils.createIntBuffer(1);

				// Create texture
				GL11.glGenTextures(idBuffer);
				GL11.glBindTexture(GL11.GL_TEXTURE_2D, idBuffer.get(0));

				// Set texture parameters
				GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_S, GL12.GL_CLAMP_TO_EDGE);
				GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_WRAP_T, GL12.GL_CLAMP_TO_EDGE);
				GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MAG_FILTER, GL11.GL_NEAREST);
				GL11.glTexParameteri(GL11.GL_TEXTURE_2D, GL11.GL_TEXTURE_MIN_FILTER, GL11.GL_NEAREST);

				GL11.glTexImage2D(
						GL11.GL_TEXTURE_2D,
						0,
						//img.getColorModel().hasAlpha() ? EXTBgra.GL_BGRA_EXT : EXTBgra.GL_BGR_EXT,
						img.getColorModel().hasAlpha() ? GL11.GL_RGBA : GL11.GL_RGB,
								img.getWidth(),
								img.getHeight(),
								0,
								//img.getColorModel().hasAlpha() ? GL11.GL_RGBA : GL11.GL_RGB,
								img.getColorModel().hasAlpha() ? EXTBgra.GL_BGRA_EXT : EXTBgra.GL_BGR_EXT,
										GL11.GL_UNSIGNED_BYTE,
										imgBuffer
				);

				// Create graphic
				g = new Graphic(idBuffer.get(0), img.getWidth(), img.getHeight(), func, 1);

				// Update maps
				textureMap.put(filename, g);
				
				int[] displayLists = new int[World.CHUNK * World.CHUNK * World.CHUNK];
				int n = GL11.glGenLists(displayLists.length);
				
				// FIXME: No array
				for (int i = 0; i < displayLists.length; i++) {
					displayLists[i] = n + i;
				}
				
				displayListMap.put(g, displayLists);
			} catch (IOException e) {
				e.printStackTrace();
				Sys.alert("Error", "Error loading texture: " + filename);
			}
		}

		return g;
	}
	
	public static Graphic getGraphic(String filename) {
		return getGraphic(filename, GraphicFunction.TEXTURE);
	}
	
	public static Graphic getGraphic(GraphicFunction func) {
		Graphic g = functionMap.get(func);
		
		if (g == null) {
			g = new Graphic(func, 1);
		
			functionMap.put(func, g);
			
			int[] displayLists = new int[World.CHUNK * World.CHUNK * World.CHUNK];
			int n = GL11.glGenLists(displayLists.length);
			
			// FIXME: No array
			for (int i = 0; i < displayLists.length; i++) {
				displayLists[i] = n + i;
			}
			
			displayListMap.put(g, displayLists);
		}
		
		return g;
	}

	public static void addToRenderSet(Entity e) {
		renderSet.add(e);
	}
	
	/**
	 * Called at start of the drawing phase.
	 */
	public static void render() {
		GL11.glClear(GL11.GL_COLOR_BUFFER_BIT | GL11.GL_DEPTH_BUFFER_BIT);

		for (Entity e : renderSet) {
			if (seenSet.contains(e)) {
				continue;
			}
			for (GraphicResource gr : e.getGraphicResources()) {
				int chunk = e.getPosition().calcChunk();
				Graphic g = gr.getGraphic();
				int displayList = displayListMap.get(g)[chunk];
				
				GL11.glNewList(displayList, GL11.GL_COMPILE);
				
				Set<Entity> set = World.getGraphicInstances(g);
				
				if (set != null) {
					for (Entity drawEntity : set) {
						if (drawEntity.getPosition().calcChunk() == chunk) {
							seenSet.add(drawEntity);
							drawEntity.draw(gr);
						}
					}
				}
				
				GL11.glEndList();
			}
		}

		Camera.viewFrom();

		for (Graphic g : textureMap.values()) {
			int[] displayLists = displayListMap.get(g);
			
			g.getFunc().initialize(g);
			for (int displayList : displayLists) {
				GL11.glCallList(displayList);
			}
			g.getFunc().finalize(g);
		}
		
		for (Graphic g : functionMap.values()) {
			int[] displayLists = displayListMap.get(g);
			
			g.getFunc().initialize(g);
			for (int displayList : displayLists) {
				GL11.glCallList(displayList);
			}
			g.getFunc().finalize(g);
		}

		renderSet.clear();
		seenSet.clear();
	}
	
	public static void drawBox(Entity e, Graphic g, int top, int front, int left, int right, int back, int bottom) {
		if (e.getExposedFaces() != 0) {
			int tilesPerRow = g.getWidth() / 32;
			float tileUnit = 1f/tilesPerRow;
			float txl = 1f/g.getWidth();

			GL11.glBegin(GL11.GL_QUADS);

			float x1 = e.position.x, y1 = e.position.y, z1 = e.position.z;
			float x2 = x1 + 1f, y2 = y1 + 1f, z2 = z1 + 1f;

			// Top Face
			if ((e.getExposedFaces() & (1 << 0)) > 0) {
				GL11.glNormal3f(0f, 1f, 0f);
				GL11.glTexCoord2f(top % tilesPerRow * tileUnit + txl, 1f - (top / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x1, y2, z2); // Bottom Left
				GL11.glTexCoord2f((top % tilesPerRow + 1) * tileUnit - txl, 1f - (top / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x2, y2, z2); // Bottom Right
				GL11.glTexCoord2f((top % tilesPerRow + 1) * tileUnit - txl, 1f - top / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x2, y2, z1); // Top Right
				GL11.glTexCoord2f(top % tilesPerRow * tileUnit + txl, 1f - top / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x1, y2, z1); // Top Left
			}

			// Front Face
			if ((e.getExposedFaces() & (1 << 1)) > 0) {
				GL11.glNormal3f(0f, 0f, 1f);
				GL11.glTexCoord2f(front % tilesPerRow * tileUnit + txl, 1f - (front / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x1, y1, z2); // Bottom Left
				GL11.glTexCoord2f((front % tilesPerRow + 1) * tileUnit - txl, 1f - (front / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x2, y1, z2); // Bottom Right
				GL11.glTexCoord2f((front % tilesPerRow + 1) * tileUnit - txl, 1f - front / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x2, y2, z2); // Top Right
				GL11.glTexCoord2f(front % tilesPerRow * tileUnit + txl, 1f - front / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x1, y2, z2); // Top Left
			}

			// Left Face
			if ((e.getExposedFaces() & (1 << 2)) > 0) {
				GL11.glNormal3f(-1f, 0f, 0f);
				GL11.glTexCoord2f(left % tilesPerRow * tileUnit + txl, 1f - (left / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x1, y1, z1); // Bottom Left
				GL11.glTexCoord2f((left % tilesPerRow + 1) * tileUnit - txl, 1f - (left / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x1, y1, z2); // Bottom Right
				GL11.glTexCoord2f((left % tilesPerRow + 1) * tileUnit - txl, 1f - left / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x1, y2, z2); // Top Right
				GL11.glTexCoord2f(left % tilesPerRow * tileUnit + txl, 1f - left / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x1, y2, z1); // Top Left
			}

			// Right Face
			if ((e.getExposedFaces() & (1 << 3)) > 0) {
				GL11.glNormal3f(1f, 0f, 0f);
				GL11.glTexCoord2f(right % tilesPerRow * tileUnit + txl, 1f - (right / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x2, y1, z2); // Bottom Left
				GL11.glTexCoord2f((right % tilesPerRow + 1) * tileUnit - txl, 1f - (right / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x2, y1, z1); // Bottom Right
				GL11.glTexCoord2f((right % tilesPerRow + 1) * tileUnit - txl, 1f - right / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x2, y2, z1); // Top Right
				GL11.glTexCoord2f(right % tilesPerRow * tileUnit + txl, 1f - right / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x2, y2, z2); // Top Left
			}

			// Back Face
			if ((e.getExposedFaces() & (1 << 4)) > 0) {
				GL11.glNormal3f(0f, 0f, -1f);
				GL11.glTexCoord2f(back % tilesPerRow * tileUnit + txl, 1f - (back / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x2, y1, z1); // Bottom Left
				GL11.glTexCoord2f((back % tilesPerRow + 1) * tileUnit - txl, 1f - (back / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x1, y1, z1); // Bottom Right
				GL11.glTexCoord2f((back % tilesPerRow + 1) * tileUnit - txl, 1f - back / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x1, y2, z1); // Top Right
				GL11.glTexCoord2f(back % tilesPerRow * tileUnit + txl, 1f - back / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x2, y2, z1); // Top Left
			}

			// Bottom Face
			if ((e.getExposedFaces() & (1 << 5)) > 0) {
				GL11.glNormal3f(0f, -1f, 0f);
				GL11.glTexCoord2f(bottom % tilesPerRow * tileUnit + txl, 1f - (bottom / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x1, y1, z1); // Bottom Left
				GL11.glTexCoord2f((bottom % tilesPerRow + 1) * tileUnit - txl, 1f - (bottom / tilesPerRow + 1) * tileUnit + txl);
				GL11.glVertex3f(x2, y1, z1); // Bottom Right
				GL11.glTexCoord2f((bottom % tilesPerRow + 1) * tileUnit - txl, 1f - bottom / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x2, y1, z2); // Top Right
				GL11.glTexCoord2f(bottom % tilesPerRow * tileUnit + txl, 1f - bottom / tilesPerRow * tileUnit - txl);
				GL11.glVertex3f(x1, y1, z2); // Top Left
			}

			GL11.glEnd();
		}
	}

	/**
	 * Converts image pixels from java default ARGB format to flipped RGBA OpenGL format.
	 * @param
	 * 			pixels		Byte array of pixels
	 * 		  	width		Width of the image
	 * 			height		Height of the image
	 * @return
	 */
	private static byte[] convertPixels(byte[] pixels, int width, int height) {
		byte[] newPixels = new byte[pixels.length];
		byte r, g, b, a;

		int i = 0;

		for (int y = 0; y < height; y++) {
			for (int x = 0; x < width; x++) {
				// Get ARGB
				i = (y * width + x) * 4;

				a = pixels[i + 0];
				r = pixels[i + 1];
				g = pixels[i + 2];
				b = pixels[i + 3];

				// Convert to RGBA and flip vertically
				i = ((height - y - 1) * width + x) * 4;

				newPixels[i + 0] = r;
				newPixels[i + 1] = g;
				newPixels[i + 2] = b;
				newPixels[i + 3] = a;
			}
		}

		return newPixels;
	}
}
