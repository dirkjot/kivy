'''
SVG
===

.. versionadded:: 1.9.0

.. warning::

    This is highly experimental and subject to change. Don't use it in
    production.


Load an SVG as a graphics instruction::

    from kivy.graphics.svg import Svg
    with widget.canvas:
        svg = Svg("image.svg")

There is no widget that can display Svg directly, you have to make your own for
now. Check the `examples/svg` for more informations.
'''

__all__ = ("Svg", )

include "common.pxi"

import re
cimport cython
from xml.etree.cElementTree import parse
from kivy.graphics.instructions cimport RenderContext
from kivy.graphics.vertex_instructions cimport Mesh, StripMesh
from kivy.graphics.tesselator cimport Tesselator
from kivy.graphics.texture cimport Texture
from kivy.graphics.vertex cimport VertexFormat
from kivy.logger import Logger
from cpython cimport array
from array import array
from cython cimport view
from time import time

DEF BEZIER_POINTS = 64 # 10
DEF CIRCLE_POINTS = 64 # 24
DEF TOLERANCE = 0.001

cdef str SVG_FS = '''
#ifdef GL_ES
    precision highp float;
#endif

varying vec4 vertex_color;
varying vec2 texcoord;
uniform sampler2D texture0;

void main (void) {
    gl_FragColor = texture2D(texture0, texcoord) * (vertex_color / 255.);
}
'''

cdef str SVG_VS = '''
#ifdef GL_ES
    precision highp float;
#endif

attribute vec2 v_pos;
attribute vec2 v_tex;
attribute vec4 v_color;
uniform mat4 modelview_mat;
uniform mat4 projection_mat;
varying vec4 vertex_color;
varying vec2 texcoord;

void main (void) {
    vertex_color = v_color;
    gl_Position = projection_mat * modelview_mat * vec4(v_pos, 0.0, 1.0);
    texcoord = v_tex;
}
'''

cdef dict colormap = {
    'aliceblue': '#f0f8ff',
    'antiquewhite': '#faebd7',
    'aqua': '#00ffff',
    'aquamarine': '#7fffd4',
    'azure': '#f0ffff',
    'beige': '#f5f5dc',
    'bisque': '#ffe4c4',
    'black': '#000000',
    'blanchedalmond': '#ffebcd',
    'blue': '#0000ff',
    'blueviolet': '#8a2be2',
    'brown': '#a52a2a',
    'burlywood': '#deb887',
    'cadetblue': '#5f9ea0',
    'chartreuse': '#7fff00',
    'chocolate': '#d2691e',
    'coral': '#ff7f50',
    'cornflowerblue': '#6495ed',
    'cornsilk': '#fff8dc',
    'crimson': '#dc143c',
    'cyan': '#00ffff',
    'darkblue': '#00008b',
    'darkcyan': '#008b8b',
    'darkgoldenrod': '#b8860b',
    'darkgray': '#a9a9a9',
    'darkgrey': '#a9a9a9',
    'darkgreen': '#006400',
    'darkkhaki': '#bdb76b',
    'darkmagenta': '#8b008b',
    'darkolivegreen': '#556b2f',
    'darkorange': '#ff8c00',
    'darkorchid': '#9932cc',
    'darkred': '#8b0000',
    'darksalmon': '#e9967a',
    'darkseagreen': '#8fbc8f',
    'darkslateblue': '#483d8b',
    'darkslategray': '#2f4f4f',
    'darkslategrey': '#2f4f4f',
    'darkturquoise': '#00ced1',
    'darkviolet': '#9400d3',
    'deeppink': '#ff1493',
    'deepskyblue': '#00bfff',
    'dimgray': '#696969',
    'dimgrey': '#696969',
    'dodgerblue': '#1e90ff',
    'firebrick': '#b22222',
    'floralwhite': '#fffaf0',
    'forestgreen': '#228b22',
    'fuchsia': '#ff00ff',
    'gainsboro': '#dcdcdc',
    'ghostwhite': '#f8f8ff',
    'gold': '#ffd700',
    'goldenrod': '#daa520',
    'gray': '#808080',
    'grey': '#808080',
    'green': '#008000',
    'greenyellow': '#adff2f',
    'honeydew': '#f0fff0',
    'hotpink': '#ff69b4',
    'indianred': '#cd5c5c',
    'indigo': '#4b0082',
    'ivory': '#fffff0',
    'khaki': '#f0e68c',
    'lavender': '#e6e6fa',
    'lavenderblush': '#fff0f5',
    'lawngreen': '#7cfc00',
    'lemonchiffon': '#fffacd',
    'lightblue': '#add8e6',
    'lightcoral': '#f08080',
    'lightcyan': '#e0ffff',
    'lightgoldenrodyellow': '#fafad2',
    'lightgreen': '#90ee90',
    'lightgray': '#d3d3d3',
    'lightgrey': '#d3d3d3',
    'lightpink': '#ffb6c1',
    'lightsalmon': '#ffa07a',
    'lightseagreen': '#20b2aa',
    'lightskyblue': '#87cefa',
    'lightslategray': '#778899',
    'lightslategrey': '#778899',
    'lightsteelblue': '#b0c4de',
    'lightyellow': '#ffffe0',
    'lime': '#00ff00',
    'limegreen': '#32cd32',
    'linen': '#faf0e6',
    'magenta': '#ff00ff',
    'maroon': '#800000',
    'mediumaquamarine': '#66cdaa',
    'mediumblue': '#0000cd',
    'mediumorchid': '#ba55d3',
    'mediumpurple': '#9370db',
    'mediumseagreen': '#3cb371',
    'mediumslateblue': '#7b68ee',
    'mediumspringgreen': '#00fa9a',
    'mediumturquoise': '#48d1cc',
    'mediumvioletred': '#c71585',
    'midnightblue': '#191970',
    'mintcream': '#f5fffa',
    'mistyrose': '#ffe4e1',
    'moccasin': '#ffe4b5',
    'navajowhite': '#ffdead',
    'navy': '#000080',
    'oldlace': '#fdf5e6',
    'olive': '#808000',
    'olivedrab': '#6b8e23',
    'orange': '#ffa500',
    'orangered': '#ff4500',
    'orchid': '#da70d6',
    'palegoldenrod': '#eee8aa',
    'palegreen': '#98fb98',
    'paleturquoise': '#afeeee',
    'palevioletred': '#db7093',
    'papayawhip': '#ffefd5',
    'peachpuff': '#ffdab9',
    'peru': '#cd853f',
    'pink': '#ffc0cb',
    'plum': '#dda0dd',
    'powderblue': '#b0e0e6',
    'purple': '#800080',
    'red': '#ff0000',
    'rosybrown': '#bc8f8f',
    'royalblue': '#4169e1',
    'saddlebrown': '#8b4513',
    'salmon': '#fa8072',
    'sandybrown': '#f4a460',
    'seagreen': '#2e8b57',
    'seashell': '#fff5ee',
    'sienna': '#a0522d',
    'silver': '#c0c0c0',
    'skyblue': '#87ceeb',
    'slateblue': '#6a5acd',
    'slategray': '#708090',
    'slategrey': '#708090',
    'snow': '#fffafa',
    'springgreen': '#00ff7f',
    'steelblue': '#4682b4',
    'tan': '#d2b48c',
    'teal': '#008080',
    'thistle': '#d8bfd8',
    'tomato': '#ff6347',
    'turquoise': '#40e0d0',
    'violet': '#ee82ee',
    'wheat': '#f5deb3',
    'white': '#ffffff',
    'whitesmoke': '#f5f5f5',
    'yellow': '#ffff00',
    'yellowgreen': '#9acd32',
}


cdef set COMMANDS = set('MmZzLlHhVvCcSsQqTtAa')
cdef set UPPERCASE = set('MZLHVCSQTA')
cdef object RE_LIST = re.compile(
    r'([A-Za-z]|-?[0-9]+\.?[0-9]*(?:e-?[0-9]*)?)')
cdef object RE_COMMAND = re.compile(
    r'([MmZzLlHhVvCcSsQqTtAa])')
cdef object RE_FLOAT = re.compile(
    r'[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?')
cdef object RE_POLYLINE = re.compile(
    r'(-?[0-9]+\.?[0-9]*(?:e-?[0-9]*)?)')
cdef object RE_TRANSFORM = re.compile(
    r'[a-zA-Z]+\([^)]*\)')

cdef VertexFormat VERTEX_FORMAT = VertexFormat(
    (b'v_pos', 2, 'float'),
    (b'v_tex', 2, 'float'),
    (b'v_color', 4, 'float'))

def _tokenize_path(pathdef):
    for x in RE_COMMAND.split(pathdef):
        if x in COMMANDS:
            yield x
        for token in RE_FLOAT.findall(x):
            yield token

cdef inline float angle(float ux, float uy, float vx, float vy):
    a = acos((ux * vx + uy * vy) / sqrt((ux ** 2 + uy ** 2) * (vx ** 2 + vy ** 2)))
    sgn = 1 if ux * vy > uy * vx else -1
    return sgn * a

cdef float parse_float(txt):
    if not txt:
        return 0.
    if txt[-2:] == 'px':
        return float(txt[:-2])
    return float(txt)

cdef list parse_list(string):
    return re.findall(RE_LIST, string)

cdef dict parse_style(string):
    cdef dict sdict = {}
    for item in string.split(';'):
        if ':' in item:
            key, value = item.split(':', 1)
            sdict[key] = value
    return sdict

cdef list kv_color_to_int_color(color):
    c = [int(255*x) for x in color]
    return c if len(c) == 4 else c + [255]

cdef parse_color(c, current_color=None):
    cdef int r, g, b, a
    if c is None or c == 'none':
        return None
    if c[0] == '#':
        c = c[1:]
    if c[:5] == 'url(#':
        return c[5:-1]
    if str(c) == 'currentColor':
        if current_color is None:
            c = 'black'
        else:
            return current_color
    if str(c) in colormap:
        c = colormap[str(c)][1:]
        r = int(c[0:2], 16)
        g = int(c[2:4], 16)
        b = int(c[4:6], 16)
        a = 255
    elif len(c) == 8:
        r = int(c[0:2], 16)
        g = int(c[2:4], 16)
        b = int(c[4:6], 16)
        a = int(c[6:8], 16)
    elif len(c) == 6:
        r = int(c[0:2], 16)
        g = int(c[2:4], 16)
        b = int(c[4:6], 16)
        a = 255
    elif len(c) == 4:
        r = int(c[0], 16) * 17
        g = int(c[1], 16) * 17
        b = int(c[2], 16) * 17
        a = int(c[3], 16) * 17
    elif len(c) == 3:
        r = int(c[0], 16) * 17
        g = int(c[1], 16) * 17
        b = int(c[2], 16) * 17
        a = 255
    else:
        # ...
        raise Exception('Invalid color format {}'.format(c))
    return [r, g, b, a]

cdef class Matrix(object):
    def __cinit__(self):
        memset(self.mat, 0, sizeof(matrix_t))

    def __init__(self, string=None):
        cdef float f
        cdef int i
        self.mat[0] = self.mat[3] = 1.
        if isinstance(string, str):
            if string.startswith('matrix('):
                i = 0
                for sf in parse_list(string[7:-1]):
                    self.mat[i] = float(sf)
                    i += 1
            elif string.startswith('translate('):
                a, b = parse_list(string[10:-1])
                self.mat[4] = float(a)
                self.mat[5] = float(b)
            elif string.startswith('scale('):
                a, b = parse_list(string[6:-1])
                self.mat[0] = float(a)
                self.mat[3] = float(b)
        elif string is not None:
            i = 0
            for f in string:
                self.mat[i] = f
                i += 1

    cdef void transform(self, float ox, float oy, float *x, float *y):
        cdef float rx = self.mat[0] * ox + self.mat[2] * oy + self.mat[4]
        cdef float ry = self.mat[1] * ox + self.mat[3] * oy + self.mat[5]
        x[0] = rx
        y[0] = ry

    cpdef Matrix inverse(self):
        cdef float d = self.mat[0] * self.mat[3] - self.mat[1]*self.mat[2]
        return Matrix([self.mat[3] / d, -self.mat[1] / d, -self.mat[2] / d, self.mat[0] / d,
                       (self.mat[2] * self.mat[5] - self.mat[3] * self.mat[4]) / d,
                       (self.mat[1] * self.mat[4] - self.mat[0] * self.mat[5]) / d])

    def __mul__(Matrix self, Matrix other):
        return Matrix([
            self.mat[0] * other.mat[0] + self.mat[2] * other.mat[1],
            self.mat[1] * other.mat[0] + self.mat[3] * other.mat[1],
            self.mat[0] * other.mat[2] + self.mat[2] * other.mat[3],
            self.mat[1] * other.mat[2] + self.mat[3] * other.mat[3],
            self.mat[0] * other.mat[4] + self.mat[2] * other.mat[5] + self.mat[4],
            self.mat[1] * other.mat[4] + self.mat[3] * other.mat[5] + self.mat[5]])


class GradientContainer(dict):
    def __init__(self, *args, **kwargs):
        dict.__init__(self, *args, **kwargs)
        self.callback_dict = {}

    def call_me_on_add(self, callback, grad_id):
        '''The client wants to know when the gradient with id grad_id gets
        added.  So store this callback for when that happens.
        When the desired gradient is added, the callback will be called
        with the gradient as the first and only argument.
        '''
        cblist = self.callback_dict.get(grad_id, None)
        if cblist == None:
            cblist = [callback]
            self.callback_dict[grad_id] = cblist
            return
        cblist.append(callback)

    def update(self, *args, **kwargs):
        raise NotImplementedError('update not done for GradientContainer')

    def __setitem__(self, key, val):
        dict.__setitem__(self, key, val)
        callbacks = self.callback_dict.get(key, [])
        for callback in callbacks:
            callback(val)


class Gradient(object):
    def __init__(self, element, svg):
        self.element = element
        self.stops = {}
        for e in element.getiterator():
            if e.tag.endswith('stop'):
                style = parse_style(e.get('style', ''))
                color = parse_color(e.get('stop-color'), svg.current_color)
                if 'stop-color' in style:
                    color = parse_color(style['stop-color'], svg.current_color)
                color[3] = int(float(e.get('stop-opacity', '1')) * 255)
                if 'stop-opacity' in style:
                    color[3] = int(float(style['stop-opacity']) * 255)
                self.stops[float(e.get('offset'))] = color
        self.stops = sorted(self.stops.items())
        self.svg = svg
        self.inv_transform = Matrix(element.get('gradientTransform')).inverse()

        inherit = self.element.get('{http://www.w3.org/1999/xlink}href')
        parent = None
        delay_params = False
        if inherit:
            parent_id = inherit[1:]
            parent = self.svg.gradients.get(parent_id, None)
            if parent == None:
                self.svg.gradients.call_me_on_add(self.tardy_gradient_parsed, parent_id)
                delay_params = True
                return
        if not delay_params:
            self.get_params(parent)

    def interp(self, float x, float y):
        cdef Matrix m = self.inv_transform
        if not self.stops:
            return [255, 0, 255, 255]
        m.transform(x, y, &x, &y)
        t = self.grad_value(x, y)
        if t < self.stops[0][0]:
            return self.stops[0][1]
        for n, top in enumerate(self.stops[1:]):
            bottom = self.stops[n]
            if t <= top[0]:
                u = bottom[0]
                v = top[0]
                alpha = (t - u)/(v - u)
                return [int(item[0] * (1 - alpha) + item[1] * alpha) for item in zip(bottom[1], top[1])]
        return self.stops[-1][1]

    def get_params(self, parent):
        for param in self.params:
            v = None
            if parent:
                v = getattr(parent, param, None)
            my_v = self.element.get(param)
            if my_v:
                v = float(my_v)
            if v:
                setattr(self, param, v)

    def tardy_gradient_parsed(self, gradient):
        self.get_params(gradient)


class LinearGradient(Gradient):
    params = ['x1', 'x2', 'y1', 'y2', 'stops']

    def grad_value(self, x, y):
        return ((x - self.x1)*(self.x2 - self.x1) + (y - self.y1)*(self.y2 - self.y1)) / ((self.x1 - self.x2)**2 + (self.y1 - self.y2)**2)


class RadialGradient(Gradient):
    params = ['cx', 'cy', 'r', 'stops']

    def grad_value(self, x, y):
        return sqrt((x - self.cx) ** 2 + (y - self.cy) ** 2)/self.r


cdef class Svg(RenderContext):
    """Svg class. See module for more informations about the usage.
    """

    def __init__(self, filename, anchor_x=0, anchor_y=0,
                 bezier_points=BEZIER_POINTS, circle_points=CIRCLE_POINTS,
                 color=None):
        '''
        Creates an SVG object from a .svg or .svgz file.

        :param str filename: The name of the file to be loaded.
        :param float anchor_x: The horizontal anchor position for scaling and
            rotations. Defaults to 0. The symbolic values 'left', 'center' and
            'right' are also accepted.
        :param float anchor_y: The vertical anchor position for scaling and
            rotations. Defaults to 0. The symbolic values 'bottom', 'center' and
            'top' are also accepted.
        :param int bezier_points: The number of line segments into which to
            subdivide Bezier splines. Defaults to 10.
        :param int circle_points: The number of line segments into which to
            subdivide circular and elliptic arcs. Defaults to 10.
        :param color the default color to use for Svg elements that specify "currentColor" 
        '''

        super(Svg, self).__init__(fs=SVG_FS, vs=SVG_VS,
                use_parent_projection=True, 
                use_parent_modelview=True)

        self.last_mesh = None
        self.paths = []
        self.width = 0
        self.height = 0
        self.line_width = 0.25

        if color is None:
            self.current_color = None
        else:
            self.current_color = kv_color_to_int_color(color)

        self.bezier_points = bezier_points
        self.circle_points = circle_points
        self.bezier_coefficients = None
        self.gradients = GradientContainer()
        self.anchor_x = anchor_x
        self.anchor_y = anchor_y
        self.line_texture = Texture.create(
                size=(2, 1), colorfmt="rgba")
        self.line_texture.blit_buffer(
                b"\xff\xff\xff\xff\xff\xff\xff\x00", colorfmt="rgba")
        self.filename = filename

    property anchor_x:
        '''
        Horizontal anchor position for scaling and rotations. Defaults to 0. The
        symbolic values 'left', 'center' and 'right' are also accepted.
        '''

        def __set__(self, anchor_x):
            self._anchor_x = anchor_x
            if self._anchor_x == 'left':
                self._a_x = 0
            elif self._anchor_x == 'center':
                self._a_x = self.width * .5
            elif self._anchor_x == 'right':
                self._a_x = self.width
            else:
                self._a_x = self._anchor_x

        def __get__(self):
            return self._anchor_x


    property anchor_y:
        '''
        Vertical anchor position for scaling and rotations. Defaults to 0. The
        symbolic values 'bottom', 'center' and 'top' are also accepted.
        '''

        def __set__(self, anchor_y):
            self._anchor_y = anchor_y
            if self._anchor_y == 'bottom':
                self._a_y = 0
            elif self._anchor_y == 'center':
                self._a_y = self.height * .5
            elif self._anchor_y == 'top':
                self._a_y = self.height
            else:
                self._a_y = self.anchor_y

        def __get__(self):
            return self._anchor_y


    '''Set the default color.

    Used for SvgElements that specify "currentColor"

    .. versionadded:: 1.9.1

    '''
    property color:
        def __set__(self, color):
            self.current_color = kv_color_to_int_color(color)
            self.reload()

    property filename:
        '''Filename to load.

        The parsing and rendering is done as soon as you set the filename.
        '''
        def __set__(self, filename):
            Logger.debug('Svg: Loading {}'.format(filename))
            # check gzip
            start = time()
            with open(filename, 'rb') as fd:
                header = fd.read(3)
            if header == '\x1f\x8b\x08':
                import gzip
                fd = gzip.open(filename, 'rb')
            else:
                fd = open(filename, 'rb')
            try:
		#save the tree for later reloading
                self.tree = parse(fd)
                self.reload()
                end = time()
                Logger.debug("Svg: Loaded {} in {:.2f}s".format(filename, end - start))
            finally:
                fd.close()

    cdef void reload(self):
            # parse tree
            start = time()
            self.parse_tree(self.tree)
            end1 = time()
            with self:
                self.render()
            end2 = time()
            Logger.debug("Svg: Parsed in {:.2f}s, rendered in {:.2f}s".format(
                    end1 - start, end2 - end1))

    cdef parse_tree(self, tree):
        root = tree._root
        self.paths = []
        self.width = parse_float(root.get('width'))
        self.height = parse_float(root.get('height'))
        if self.height:
            self.transform = Matrix([1, 0, 0, -1, 0, self.height])
        else:
            x, y, w, h = [parse_float(x) for x in
                    parse_list(root.get('viewBox'))]
            self.transform = Matrix([1, 0, 0, -1, -x, h + y])
            self.height = h
            self.width = w

        self.opacity = 1.0
        for e in root.getchildren():
            self.parse_element(e)

    cdef parse_element(self, e):
        self.fill = parse_color(e.get('fill'), self.current_color)
        self.stroke = parse_color(e.get('stroke'), self.current_color)
        oldopacity = self.opacity
        self.opacity *= float(e.get('opacity', 1))
        fill_opacity = float(e.get('fill-opacity', 1))
        stroke_opacity = float(e.get('stroke-opacity', 1))

        oldtransform = self.transform
        for t in self.parse_transform(e.get('transform')):
            self.transform *= Matrix(t)

        style = e.get('style')
        if style:
            sdict = parse_style(style)
            if 'fill' in sdict:
                self.fill = parse_color(sdict['fill'], self.current_color)
            if 'fill-opacity' in sdict:
                fill_opacity *= float(sdict['fill-opacity'])
            if 'stroke' in sdict:
                self.stroke = parse_color(sdict['stroke'], self.current_color)
            if 'stroke-opacity' in sdict:
                stroke_opacity *= float(sdict['stroke-opacity'])

        if self.fill is None:
            self.fill = [0, 0, 0, 255]
        if self.stroke is None:
            self.stroke = [0, 0, 0, 0]
        if isinstance(self.stroke, list):
            self.stroke[3] = int(self.opacity * stroke_opacity * self.stroke[3])
        if isinstance(self.fill, list):
            self.fill[3] = int(self.opacity * fill_opacity * self.fill[3])
        if isinstance(self.stroke, list) and self.stroke[3] == 0:
            self.stroke = self.fill #Stroked edges antialias better

        if e.tag.endswith('path'):
            self.parse_path(e.get('d', ''))

        elif e.tag.endswith('rect'):
            x = 0
            y = 0
            if 'x' in e.keys():
                x = float(e.get('x'))
            if 'y' in e.keys():
                y = float(e.get('y'))
            h = float(e.get('height'))
            w = float(e.get('width'))
            self.new_path()
            self.set_position(x, y)
            self.set_position(x + w, y)
            self.set_position(x + w, y + h)
            self.set_position(x, y + h)
            self.set_position(x, y)
            self.end_path()

        elif e.tag.endswith('polyline') or e.tag.endswith('polygon'):
            pathdata = e.get('points')
            pathdata = re.findall(RE_POLYLINE, pathdata)
            pathdata.reverse()

            self.new_path()
            while pathdata:
                self.set_position(
                    float(pathdata.pop()),
                    float(pathdata.pop()))
            if e.tag.endswith('polygon'):
                self.close_path()
            self.end_path()

        elif e.tag.endswith('line'):
            x1 = float(e.get('x1'))
            y1 = float(e.get('y1'))
            x2 = float(e.get('x2'))
            y2 = float(e.get('y2'))
            self.new_path()
            self.set_position(x1, y1)
            self.set_position(x2, y2)
            self.end_path()

        elif e.tag.endswith('circle'):
            cx = float(e.get('cx'))
            cy = float(e.get('cy'))
            r = float(e.get('r'))
            self.new_path()
            for i in xrange(self.circle_points):
                theta = 2 * i * pi / self.circle_points
                self.set_position(cx + r * cos(theta), cy + r * sin(theta))
            self.close_path()
            self.end_path()

        elif e.tag.endswith('ellipse'):
            cx = float(e.get('cx'))
            cy = float(e.get('cy'))
            rx = float(e.get('rx'))
            ry = float(e.get('ry'))
            self.new_path()
            for i in xrange(self.circle_points):
                theta = 2 * i * pi / self.circle_points
                self.set_position(cx + rx * cos(theta), cy + ry * sin(theta))
            self.close_path()
            self.end_path()

        elif e.tag.endswith('linearGradient'):
            self.gradients[e.get('id')] = LinearGradient(e, self)

        elif e.tag.endswith('radialGradient'):
            self.gradients[e.get('id')] = RadialGradient(e, self)

        for c in e.getchildren():
            self.parse_element(c)

        self.transform = oldtransform
        self.opacity = oldopacity

    cdef list parse_transform(self, transform_def):
        if isinstance(transform_def, str):
            return RE_TRANSFORM.findall(transform_def)
        else:
            return [transform_def]

    cdef parse_path(self, pathdef):
        # In the SVG specs, initial movetos are absolute, even if
        # specified as 'm'. This is the default behavior here as well.
        # But if you pass in a current_pos variable, the initial moveto
        # will be relative to that current_pos. This is useful.
        elements = list(_tokenize_path(pathdef))
        # Reverse for easy use of .pop()
        elements.reverse()
        command = None

        self.new_path()

        while elements:

            if elements[-1] in COMMANDS:
                # New command.
                last_command = command # Used by S and T
                command = elements.pop()
                absolute = command in UPPERCASE
                command = command.upper()
            else:
                # If this element starts with numbers, it is an implicit command
                # and we don't change the command. Check that it's allowed:
                if command is None:
                    raise ValueError("Unallowed implicit command in %s, position %s" % (
                        pathdef, len(pathdef.split()) - len(elements)))


            if command == 'M':
                # Moveto command. This is like "picking up the pen", so
                # start a new loop.
                if len(self.loop):
                    self.path.append(self.loop)
                    self.loop = array('f', [])

                x = float(elements.pop())
                y = float(elements.pop())
                self.set_position(x, y, absolute)

                # Implicit moveto commands are treated as lineto commands.
                # So we set command to lineto here, in case there are
                # further implicit commands after this moveto.
                command = 'L'

            elif command == 'Z':
                self.close_path()

            elif command == 'L':
                x = float(elements.pop())
                y = float(elements.pop())
                self.set_position(x, y, absolute)

            elif command == 'H':
                x = float(elements.pop())
                if absolute:
                    self.set_position(x, self.y)
                else:
                    self.set_position(self.x + x, self.y)

            elif command == 'V':
                y = float(elements.pop())
                if absolute:
                    self.set_position(self.x, y)
                else:
                    self.set_position(self.x, self.y + y)

            elif command == 'C':
                c1x = float(elements.pop())
                c1y = float(elements.pop())
                c2x = float(elements.pop())
                c2y = float(elements.pop())
                endx = float(elements.pop())
                endy = float(elements.pop())

                if not absolute:
                    c1x += self.x
                    c1y += self.y
                    c2x += self.x
                    c2y += self.y
                    endx += self.x
                    endy += self.y

                self.curve_to(c1x, c1y, c2x, c2y, endx, endy)

            elif command == 'S':
                # Smooth curve. First control point is the "reflection" of
                # the second control point in the previous path.

                if last_command not in 'CS':
                    # If there is no previous command or if the previous command
                    # was not an C, c, S or s, assume the first control point is
                    # coincident with the current point.
                    c1x = self.x
                    c1y = self.y
                else:
                    # The first control point is assumed to be the reflection of
                    # the second control point on the previous command relative
                    # to the current point.
                    c1x = self.last_cx
                    c1y = self.last_cy

                c2x = float(elements.pop())
                c2y = float(elements.pop())
                endx = float(elements.pop())
                endy = float(elements.pop())

                if not absolute:
                    c2x += self.x
                    c2y += self.y
                    endx += self.x
                    endy += self.y

                self.curve_to(c1x, c1y, c2x, c2y, endx, endy)

            elif command == 'A':
                rx = float(elements.pop())
                ry = float(elements.pop())
                rotation = float(elements.pop())
                arc = float(elements.pop())
                sweep = float(elements.pop())            
                x = float(elements.pop())
                y = float(elements.pop())

                if not absolute:
                    x += self.x
                    y += self.y

                self.arc_to(rx, ry, rotation, arc, sweep, x, y)

            else:
                Logger.warning('Svg: unimplemented command {}'.format(command))

            '''
            elif command == 'Q':
                control = float(elements.pop()) + float(elements.pop()) * 1j
                end = float(elements.pop()) + float(elements.pop()) * 1j
                
                if not absolute:
                    control += current_pos
                    end += current_pos
                    
                segments.append(path.QuadraticBezier(current_pos, control, end))
                current_pos = end

            elif command == 'T':
                # Smooth curve. Control point is the "reflection" of
                # the second control point in the previous path.
                
                if last_command not in 'QT':
                    # If there is no previous command or if the previous command
                    # was not an Q, q, T or t, assume the first control point is
                    # coincident with the current point.
                    control = current_pos
                else:
                    # The control point is assumed to be the reflection of
                    # the control point on the previous command relative
                    # to the current point.
                    control = current_pos + current_pos - segments[-1].control2
                    
                end = float(elements.pop()) + float(elements.pop()) * 1j
                
                if not absolute:
                    control += current_pos
                    end += current_pos
                    
                segments.append(path.QuadraticBezier(current_pos, control, end))
                current_pos = end
            '''

        self.end_path()

    cdef void new_path(self):
        self.x = 0
        self.y = 0
        self.close_index = 0
        self.path = []
        self.loop = array('f', [])

    cdef void close_path(self):
        #self.loop.append(self.loop[0])
        #self.loop.append(self.loop[1])
        self.path.append(self.loop)
        self.loop = array('f', [])

    cdef void set_position(self, float x, float y, int absolute=1):
        if absolute:
            self.x = x
            self.y = y
        else:
            self.x += x
            self.y += y
        self.loop.append(self.x)
        self.loop.append(self.y)

    cdef arc_to(self, float rx, float ry, float phi, float large_arc,
            float sweep, float x, float y):
        # This function is made out of magical fairy dust
        # http://www.w3.org/TR/2003/REC-SVG11-20030114/implnote.html#ArcImplementationNotes
        cdef float x1, y1, x2, y2, cp, sp, dx, dy, x_, y_, r2, cx_, cy_, cx, cy
        cdef float psi, delta, ct, st, theta
        cdef int n_points, i
        x1 = self.x
        y1 = self.y
        x2 = x
        y2 = y
        cp = cos(phi)
        sp = sin(phi)
        dx = .5 * (x1 - x2)
        dy = .5 * (y1 - y2)
        x_ = cp * dx + sp * dy
        y_ = -sp * dx + cp * dy
        r2 = (((rx * ry)**2 - (rx * y_)**2 - (ry * x_)**2)/
	      ((rx * y_)**2 + (ry * x_)**2))
        if r2 < 0: r2 = 0
        r = sqrt(r2)
        if large_arc == sweep:
            r = -r
        cx_ = r * rx * y_ / ry
        cy_ = -r * ry * x_ / rx
        cx = cp * cx_ - sp * cy_ + .5 * (x1 + x2)
        cy = sp * cx_ + cp * cy_ + .5 * (y1 + y2)

        psi = angle(1, 0, (x_ - cx_) / rx, (y_ - cy_) / ry)
        delta = angle((x_ - cx_) / rx, (y_ - cy_) / ry,
                      (-x_ - cx_) / rx, (-y_ - cy_) / ry)
        if sweep and delta < 0: delta += pi * 2
        if not sweep and delta > 0: delta -= pi * 2
        n_points = <int>fabs(self.circle_points * delta / (2 * pi))
        if n_points < 1:
            n_points = 1

        for i in xrange(n_points + 1):
            theta = psi + i * delta / n_points
            ct = cos(theta)
            st = sin(theta)
            self.set_position(cp * rx * ct - sp * ry * st + cx,
                    sp * rx * ct + cp * ry * st + cy)


    @cython.boundscheck(False)
    cdef void curve_to(self, float x1, float y1, float x2, float y2,
            float x, float y):
        cdef int bp_count = self.bezier_points + 1
        cdef int i, count, ilast
        cdef float t, t0, t1, t2, t3, px = 0, py = 0
        cdef list bc
        cdef array.array loop
        cdef float* f_loop
        cdef float[:] f_bc

        if self.bezier_coefficients is None:
            self.bezier_coefficients = view.array(
                    shape=(bp_count * 4, ),
                    itemsize=sizeof(float),
                    format="f")
            f_bc = self.bezier_coefficients
            for i in range(bp_count):
                t = float(i) / self.bezier_points
                t0 = (1 - t) ** 3
                t1 = 3 * t * (1 - t) ** 2
                t2 = 3 * t ** 2 * (1 - t)
                t3 = t ** 3
                f_bc[i * 4] = t0
                f_bc[i * 4 + 1] = t1
                f_bc[i * 4 + 2] = t2
                f_bc[i * 4 + 3] = t3
        else:
            f_bc = self.bezier_coefficients

        self.last_cx = x2
        self.last_cy = y2
        count = bp_count * 2
        ilast = len(self.loop)
        array.resize(self.loop, ilast + count)
        f_loop = self.loop.data.as_floats
        for i in range(bp_count):
            t0 = f_bc[i * 4]
            t1 = f_bc[i * 4 + 1]
            t2 = f_bc[i * 4 + 2]
            t3 = f_bc[i * 4 + 3]
            f_loop[ilast + i * 2] = px = t0 * self.x + t1 * x1 + t2 * x2 + t3 * x
            f_loop[ilast + i * 2 + 1] = py = t0 * self.y + t1 * y1 + t2 * y2 + t3 * y

        self.x, self.y = px, py

    cdef void end_path(self):
        if len(self.loop):
            self.path.append(self.loop)
        tris = None
        cdef Tesselator tess
        cdef array.array loop
        if self.fill:
            tess = Tesselator()
            for loop in self.path:
                tess.add_contour_data(loop.data.as_voidptr, len(loop) / 2)
            tess.tesselate()
            tris = tess.vertices

        # Add the stroke for the first subpath, and the fill for all
        # subpaths.
        self.paths.append((
            self.path[0] if self.stroke else None,
            self.stroke,
            tris,
            self.fill,
            self.transform))

        # Finally, add the stroke for second and subsequent subpaths
        if self.stroke and len(self.path) > 1:
            for loop in self.path[1:]:
                self.paths.append((
                    loop,
                    self.stroke,
                    None,
                    None,
                    self.transform))
        self.path = []

    @cython.boundscheck(False)
    cdef void push_mesh(self, float[:] path, fill, Matrix transform, mode):
        cdef float *vertices
        cdef int index, vindex
        cdef float *f_tris
        cdef float x, y, r, g, b, a
        cdef Mesh mesh

        cdef int count = len(path) / 2
        vertices = <float *>malloc(sizeof(float) * count * 8)
        if vertices == NULL:
            return
        vindex = 0

        if isinstance(fill, str):
            gradient = self.gradients[fill]
            for index in range(count):
                x = path[index * 2]
                y = path[index * 2 + 1]
                r, g, b, a = gradient.interp(x, y)
                transform.transform(x, y, &x, &y)
                vertices[vindex] = x
                vertices[vindex + 1] = y
                vertices[vindex + 2] = 0
                vertices[vindex + 3] = 0
                vertices[vindex + 4] = r
                vertices[vindex + 5] = g
                vertices[vindex + 6] = b
                vertices[vindex + 7] = a
                vindex += 8
        else:
            r, g, b, a = fill
            for index in range(count):
                x = path[index * 2]
                y = path[index * 2 + 1]
                transform.transform(x, y, &x, &y)
                vertices[vindex] = x
                vertices[vindex + 1] = y
                vertices[vindex + 2] = 0
                vertices[vindex + 3] = 0
                vertices[vindex + 4] = r
                vertices[vindex + 5] = g
                vertices[vindex + 6] = b
                vertices[vindex + 7] = a
                vindex += 8

        self.push_strip_mesh(vertices, vindex, count)
        free(vertices)

    cdef void push_strip_mesh(self, float *vertices, int vindex, int count,
            int mode=0):
        if self.last_mesh:
            if self.last_mesh.add_triangle_strip(vertices, vindex, count, mode):
                return
        self.last_mesh = StripMesh(fmt=VERTEX_FORMAT)
        self.last_mesh.add_triangle_strip(vertices, vindex, count, mode)

    cdef void push_line_mesh(self, float[:] path, fill, Matrix transform):
        # Tentative to use smooth line, doesn't work completly yet.
        # Caps and joint are missing
        cdef int index, vindex = 0, odd = 0, i
        cdef float ax, ay, bx, _by, r = 0, g = 0, b = 0, a = 0
        cdef int count = len(path) / 2
        cdef float *vertices = NULL
        cdef float width = self.line_width
        vindex = 0

        vertices = <float *>malloc(sizeof(float) * count * 32)
        if vertices == NULL:
            return

        if not isinstance(fill, str):
            r, g, b, a = fill

        for index in range(count):
            i = index * 2
            ax = path[i]
            ay = path[i + 1]
            if index == count - 1:
                i = 0
            else:
                i = index * 2 + 2
            bx = path[i]
            _by = path[i + 1]
            transform.transform(ax, ay, &ax, &ay)
            transform.transform(bx, _by, &bx, &_by)

            rx = bx - ax
            ry = _by - ay
            angle = atan2(ry, rx)
            a1 = angle - PI2
            a2 = angle + PI2

            cos1 = cos(a1) * width
            sin1 = sin(a1) * width
            cos2 = cos(a2) * width
            sin2 = sin(a2) * width

            x1 = ax + cos1
            y1 = ay + sin1
            x4 = ax + cos2
            y4 = ay + sin2
            x2 = bx + cos1
            y2 = _by + sin1
            x3 = bx + cos2
            y3 = _by + sin2

            if isinstance(fill, str):
                g = self.gradients[fill]
                r, g, b, a = g.interp(ax, ay)

            vertices[vindex + 2] = vertices[vindex + 10] = \
                vertices[vindex + 18] = vertices[vindex + 26] = 0
            vertices[vindex + 3] = vertices[vindex + 11] = \
                vertices[vindex + 19] = vertices[vindex + 27] = 0
            vertices[vindex + 4] = vertices[vindex + 12] = \
                vertices[vindex + 20] = vertices[vindex + 28] = r
            vertices[vindex + 5] = vertices[vindex + 13] = \
                vertices[vindex + 21] = vertices[vindex + 29] = g
            vertices[vindex + 6] = vertices[vindex + 14] = \
                vertices[vindex + 22] = vertices[vindex + 30] = b
            vertices[vindex + 7] = vertices[vindex + 15] = \
                vertices[vindex + 23] = vertices[vindex + 31] = a

            vertices[vindex + 0] = x1
            vertices[vindex + 1] = y1
            vertices[vindex + 8] = x4
            vertices[vindex + 9] = y4
            vertices[vindex + 16] = x2
            vertices[vindex + 17] = y2
            vertices[vindex + 24] = x3
            vertices[vindex + 25] = y3
            vindex += 32

        self.push_strip_mesh(vertices, vindex, (vindex / 32) * 4, 1)
        free(vertices)

    cdef void render(self):
        for path, stroke, tris, fill, transform in self.paths:
            if tris:
                for item in tris:
                    self.push_mesh(item, fill, transform, 'triangle_strip')
            if path:
                self.push_line_mesh(path, stroke, transform)
