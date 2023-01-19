FROM quay.io/openshift/origin-must-gather:4.13

# Save original gather script
RUN mv /usr/bin/gather /usr/bin/gather_original

# Use our gather script in place of the original one
COPY gather_gitops.sh /usr/bin/gather

# Make it executable
RUN chmod +x /usr/bin/gather

ENTRYPOINT /usr/bin/gather