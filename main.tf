apiVersion: apps/v1
kind: Deployment
metadata:
  name: PLACEHOLDER_APP_NAME
  namespace: PLACEHOLDER_APP_NAME-PLACEHOLDER_ENVIRONMENT
  labels:
    app: PLACEHOLDER_APP_NAME
    environment: PLACEHOLDER_ENVIRONMENT
spec:
  revisionHistoryLimit: 10
  progressDeadlineSeconds: 300
  selector:
    matchLabels:
      app: PLACEHOLDER_APP_NAME
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0
  template:
    metadata:
      annotations:
        admission.datadoghq.com/enabled: "true"
        admission.datadoghq.com/PLACEHOLDER_DD_LANG-lib.version: "PLACEHOLDER_DD_LIB_VERSION"
      labels:
        admission.datadoghq.com/enabled: "true"
        app: PLACEHOLDER_APP_NAME
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: "karpenter.sh/nodepool"
                operator: In
                values:
                - "default"
      containers:
        - name: PLACEHOLDER_APP_NAME
          image: PLACEHOLDER_ECR_IMAGE
          imagePullPolicy: Always
          envFrom:
            - configMapRef:
                name: PLACEHOLDER_APP_NAME-app-vars
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: PLACEHOLDER_REQUESTS_CPU
              memory: PLACEHOLDER_REQUESTS_MEMORY
            limits:
              cpu: PLACEHOLDER_LIMITS_CPU
              memory: PLACEHOLDER_LIMITS_MEMORY
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
            successThreshold: 1
            failureThreshold: 3
#          livenessProbe:
#            tcpSocket:
#              port: 8080
#            initialDelaySeconds: 30
#            periodSeconds: 10


 
