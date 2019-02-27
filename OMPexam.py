
from PyQt4 import QtCore, QtGui, uic
from omp_fort import omp_fort
import os

window_file = uic.loadUiType("./GUI/OMPWind.ui")[0]
class Window(QtGui.QMainWindow, window_file):
    def __init__(self, parent=None):
        QtGui.QMainWindow.__init__(self, parent)
        self.setupUi(self)
        self.centre()
        self.log = Log(self)
        self.log.show()
        self.fixShape.setEnabled(False)
        self.initGraphics()
        self.logText = self.log.Log.append

        # Initialise Buttons and options
        self.runButton.clicked.connect(self.runExample)
        self.stopButton.clicked.connect(self.stopButt)
        self.jobShapeCB.currentIndexChanged.connect(self.enableFix)

        self.threadPool = QtCore.QThreadPool()
        
    def runExample(self):
        # Reset running status
        self.stopped = False
        self.runButton.setEnabled(False)

        # Set up parameters from inputs
        omp_fort.sched = self.scheduleCB.currentIndex()
        omp_fort.num_rect = self.numJobSB.value()
        omp_fort.job_wait = self.jobTSB.value()
        omp_fort.chunk = self.chunkSB.value()
        omp_fort.num_threads = self.threadSB.value()
        omp_fort.max_height = self.GV.height() - 30
        omp_fort.init(self.jobShapeCB.currentIndex(), self.fixShape.isChecked())

        # Remove old data
        self.GV.scene.clear()
        self.GV.bars = []
        self.GV.bars_done = []

        #Calculate bar properties
        num_rect = omp_fort.num_rect
        maxBarWidth = min((self.Gwidth-20)/num_rect,75) #20px space at edge, max of 50 (75 - space)
        space =max(0.3*maxBarWidth, 5) # Minimum space is 5
        barWidth = maxBarWidth-space # Each bar needs to account for separation
        initPosition = max(-self.HGwidth+10, -(num_rect/2.)*maxBarWidth)

        
        # Draw initial boxes
        position = initPosition
        for i in omp_fort.rect_height:
            self.GV.bars.append(self.GV.scene.addRect(position,self.HGheight-i,barWidth,i,pen=self.GV.pen,brush=self.GV.brush))
            self.GV.bars_done.append(self.GV.scene.addRect(position,self.HGheight,barWidth,i,pen=self.GV.done_pens[0],brush=self.GV.done_brushes[0]))
            position += space + barWidth

        # Force refresh of graphics with new structures
        app.processEvents()

        # Start omp
        self.fortThread = FortThread()
        self.threadPool.start(self.fortThread)

        # Start self proliferating update train on subthread
        self.update()

        # Main thread handles UI processing
        while (omp_fort.finished == 0):
            app.processEvents()

        # Write final info
        if (omp_fort.finished == 1 and not self.stopped):
            
            self.logText(" Thread  | Time (s) |  Load (%)")
            self.logText(" ------------------------------- ")
            for i in range(omp_fort.num_threads):
                self.logText("{:^9d}| {:^8.3f} | {:^7.4f}".format(i+1, omp_fort.time[i], omp_fort.my_work[i]))
            self.logText(" ------------------------------- ")
            self.logText(" Final time: {} ".format(max(omp_fort.time)))
            self.logText(" ------------------------------- ")

        # Final clear up and reset data
        self.update()
        self.runButton.setEnabled(True)
        
    def update(self):
        # Pull Fortran info and push to bars. Overcosted, but not performance critical
        temp1 = omp_fort.rect_done[:]
        for i in range(len(temp1)):
            temp = self.GV.bars_done[i].rect()
            self.GV.bars_done[i].setRect(temp.x(),self.HGheight-temp1[i],temp.width(),temp.height())
            self.GV.bars_done[i].setBrush(self.GV.done_brushes[omp_fort.job_done_by[i]])
            self.GV.bars_done[i].setPen(self.GV.done_pens[omp_fort.job_done_by[i]])
        self.GV.scene.update()
        
        if (omp_fort.finished == 0): QtCore.QTimer.singleShot(10,self.update)

    def initGraphics(self):
        # Set up initial data
        self.GV=self.graphicsView
        self.GV.scene = QtGui.QGraphicsScene(self)
        self.GV.setScene(self.GV.scene)
        self.Gwidth = self.GV.width()
        self.Gheight = self.GV.height()
        self.HGheight = self.Gheight/2
        self.HGwidth  = self.Gwidth/2
        # Initialise drawing colours
        self.GV.pen = QtGui.QPen(QtGui.QColor(255,0,0))
        self.GV.brush = QtGui.QBrush(QtGui.QColor(255,0,0))
        colours = [QtGui.QColor(0,0,0),QtGui.QColor(255,247,0),QtGui.QColor(75,0,130),QtGui.QColor(255,165,0),QtGui.QColor(138,43,226),QtGui.QColor(41,171,135),QtGui.QColor(220,20,60),QtGui.QColor(111,78,55),QtGui.QColor(255,255,240),QtGui.QColor(209,226,49),QtGui.QColor(184,115,51)]
        self.GV.done_brushes = [QtGui.QBrush(colour) for colour in colours]
        self.GV.done_pens    = [QtGui.QPen(colour) for colour in colours]

        # Centre view on 0,0
        self.GV.setSceneRect(-self.HGwidth,-self.HGheight,self.Gwidth-3,self.Gheight-3)

    def stopButt(self):
        omp_fort.computing=False
        self.stopped = True

    def enableFix(self):
        if (self.jobShapeCB.currentIndex() == 3):
            self.fixShape.setEnabled(True)
        else:
            self.fixShape.setChecked(False)
            self.fixShape.setEnabled(False)

    #Moves window to centre of screen
    def centre(self):
        frameGm = self.frameGeometry()
        frameGm.moveCenter(QtGui.QApplication.desktop().screenGeometry(QtGui.QApplication.desktop().screenNumber(QtGui.QApplication.desktop().cursor().pos())).center())
        self.move(frameGm.topLeft())

     #When this window closes
    def closeEvent(self, event):
        os._exit(1)

log_file = uic.loadUiType("./GUI/RunLog.ui")[0]
class Log(QtGui.QMainWindow, log_file):
    def __init__(self, parent=None):
        QtGui.QMainWindow.__init__(self, parent)
        self.setupUi(self)
        self.centre()
        self.clearButton.clicked.connect(self.clear)

    def clear(self):
        self.Log.setText("")

    def centre(self):
        frameGm = self.frameGeometry()
        frameGm.moveCenter(QtGui.QApplication.desktop().screenGeometry(QtGui.QApplication.desktop().screenNumber(QtGui.QApplication.desktop().cursor().pos())).center())
        self.move(frameGm.topRight())

    def closeEvent(self, event):
        os._exit(1)

class FortThread(QtCore.QRunnable):
    def run(self):
        omp_fort.run()
        
#Initialise the GUI thread
QtCore.QCoreApplication.setAttribute(QtCore.Qt.AA_X11InitThreads)
app = QtGui.QApplication([])

#Show the startup window
window = Window(None)
window.show()

app.exec_()
